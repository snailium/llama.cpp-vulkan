# Why checkpoints are constant-size here: the mechanism, from source + measurement

**Date:** 2026-10-24 · **Card:** RX 7900 XTX · **Image:** v0.7.0 (`620d222`)
**Config:** Qwen3.8-27B-Q4_K_M, ctx 131072, KV q8_0/q4_0, MTP4, np 1.

This closes the open question left by
[2026-10-24-xtx-130k-depth-no-oom.md](2026-10-24-xtx-130k-depth-no-oom.md): *why* does the
checkpoint cost plateau instead of scaling with depth?

The answer is that **a checkpoint does not contain the attention KV cache at all for this
model.** It contains the recurrent state, which is a fixed-size single snapshot.

## Proof 1 — measured: size is constant regardless of depth

`SLT_TRC`/`SLT_WRN` print each checkpoint's size. With `--ctx-checkpoints 3` to force
evictions, the sizes from depth 65,290 to 124,060:

```
pos_min =  65289, n_tokens =  65290, size = 149.626 MiB
pos_min =  68554, n_tokens =  68555, size = 149.626 MiB
pos_min =  71819, n_tokens =  71820, size = 149.626 MiB
   ...                       (18 more, all identical)                      ...
pos_min = 124059, n_tokens = 124060, size = 149.626 MiB
```

Depth nearly doubles; size does not move. So the per-token model (27,734 B/token) cannot
apply to checkpoints.

## Proof 2 — source: the attention KV is skipped by design

Checkpoints are created with `LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY`
(`server-context.cpp`, `create_checkpoint` → `cur.update_tgt(ctx_tgt, slot.id, PARTIAL_ONLY)`).

`src/llama-kv-cache.cpp:2079` and `:2160`:

```c
void llama_kv_cache::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    if ((flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) && swa_type == LLAMA_SWA_TYPE_NONE) {
        return;          // writes nothing
    }
```

Our model reports `n_swa = 0` / `is_swa_any = 0`, so `swa_type == LLAMA_SWA_TYPE_NONE` and the
KV write returns immediately. **Zero KV bytes in the checkpoint.**

## Proof 3 — source + startup log: what *is* stored is 149.62 MiB of recurrent state

```
llama_memory_recurrent: size =  149.62 MiB (     1 cells,  64 layers,  1 seqs  0 rs_seq)
                                      R (f32):    5.62 MiB, S (f32):  144.00 MiB
llama_kv_cache:         size = 3328.00 MiB (131072 cells,  16 layers,  1/1 seqs)
                                      K (q8_0): 2176.00 MiB, V(q4_0): 1152.00 MiB
```

**The recurrent memory has exactly 1 cell** — one snapshot, not one per token. Its size,
149.62 MiB, is the checkpoint's size to the last digit. The KV cache, by contrast, has
131,072 cells and 3,328 MiB (confirming 26,624 B/token), and all of it is excluded.

## The complete arithmetic

| quantity | value | source |
|---|---|---|
| one checkpoint | **149.626 MiB** | measured, constant 65k→124k |
| live set cap | 32 (`--ctx-checkpoints` default) | `create_checkpoint` eviction loop |
| **plateau** | **32 x 149.626 = 4,788 MiB = 4.68 GiB** | arithmetic |
| baseline RSS (no checkpoints) | 1,860 MiB | measured, `--ctx-checkpoints 0` |
| **predicted total** | **6,648 MiB** | 1,860 + 4,788 |
| **measured total** | **6,503 MiB** | 130k depth run |

Within 2 % (a couple of slots hold fewer than 32).

It also explains the earlier confusion: the 8-turn run grew **455 MiB per turn**, and
455 / 149.6 = **3.04** — roughly **three checkpoints per turn** (the code breaks at a
user-message boundary, at `4 + n_ubatch`, and at `4` before the end of the prompt). 32 slots /
3 per turn ≈ **11 turns to saturation**, and the plateau began at **turn 10**. The linear phase
was simply "the list is not full yet".

## The general rule (this is what to carry forward)

`do_checkpoint` is true when `seq_rm type == FULL || RS || n_swa > 0`. What that means for cost:

| model shape | seq_rm type | checkpoints? | size |
|---|---|---|---|
| dense, no SWA | PART | **no** | — |
| **hybrid (recurrent + attention), no SWA — ours** | **FULL** | **yes** | **constant** ≈ one recurrent snapshot (149.6 MiB here), KV excluded |
| SWA (any) | FULL or n_swa > 0 | yes | **depth-proportional** — KV is included because `swa_type != NONE` |

**The BC-250 report's depth-proportional finding is correct for an SWA model and wrong for
ours.** Its `n_tokens x 26,624` measurement came from a model whose `swa_type` was not NONE, so
the KV was serialised. Copying that model to a non-SWA hybrid is the exact mistake this report
corrects — and it is the mistake I made when I wrote the earlier budget table.

**How to tell which regime you are in, in one command** (no long run needed):

```bash
docker run --rm --device /dev/dri -e VK_DRIVER_FILES=... <image> \
  --model <model> --ctx-size 131072 --n-gpu-layers 999 -lv 5 2>&1 \
  | grep -E "llama_memory_recurrent: size =|print_info: n_swa"
```

`n_swa = 0` + `recurrent: ... ( 1 cells,` → checkpoints are **constant cost**.
`n_swa > 0` → checkpoints are **depth-proportional**; then use the per-token formula.

## Corrected cost model

```
if n_swa == 0 and the model has recurrent layers:
    checkpoint bytes  = recurrent_snapshot_size            (constant; 149.626 MiB here)
    worst case        = n_ctx_checkpoints x that           (4.68 GiB at the default 32)
elif n_swa > 0:
    checkpoint bytes  = n_tokens_of_that_sequence x (target_KV + draft_KV) per token
    worst case        = n_ctx_checkpoints x max_depth x that
```

## Honest boundaries

1. **One model, one image.** The 149.626 MiB is this model's recurrent snapshot
   (R 5.62 + S 144.00 MiB). It scales with layer count and state geometry, not with context.
2. **The "3 checkpoints per turn" is inferred** from 455/149.6 = 3.04 and corroborated by
   saturation at turn ~10; I did not count create lines per turn directly.
3. **The draft/spec state is folded into the same 149.626 MiB** here — `size()` sums
   `data_tgt + data_dft + data_spec`, and the number matches `llama_memory_recurrent size`
   exactly, so the draft term is negligible for this model.
4. **Verified at ctx 131072 only.** The recurrent snapshot size does not depend on `-c`, so
   this should hold at other context sizes, but that is inference, not measurement.

## Artifacts

`/models/ckpt/sizes.log`, `sizes.json` on `.101`; `sizes.sh`.
