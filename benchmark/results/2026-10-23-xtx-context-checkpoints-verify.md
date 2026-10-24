# Context checkpoints on the XTX: verified, and the production number

**Date:** 2026-10-23 · **Card:** RX 7900 XTX (Vulkan/RADV) · **Image:** `:latest` = v0.7.0 (`620d222`)
**Config:** production exactly — Qwen3.8-27B-Q4_K_M, ctx 131072, KV **q8_0 K / q4_0 V**,
MTP4 draft (draft KV q8_0/q4_0), FA on, `--parallel 1`, `--cache-ram 0` for the A/B only.

Verifies the BC-250 claim in `Bonsai2/bonsai2-work/CONTEXT-CHECKPOINTS-xtx-verify.md`.

## Verdict: the claim holds on this model, and it is worse than the BC-250 estimate

Two corrections to the source report, both measured here:

1. **This model DOES create checkpoints.** Startup says
   `common_conte: the context does not support partial sequence removal` → seq_rm type
   **FULL** → `do_checkpoint = true`. (`n_swa = 0`, `is_swa_any = 0`, so the SWA branch is
   irrelevant.) Prediction 1 in §7 of that report is refuted; the cost model is live here.
2. **Production KV is q8_0/q4_0, not q4_0/q4_0.** The report's §5 budget used 18,432 B/token;
   the real target term is **26,624 B/token**, so every number in its table is ~30 % low.

## Why 26,624 B/token is exact for this model

`qwen35` is a **hybrid**: `attention.recurrent_layers` is `arr[bool,64]` with the pattern
`1,1,1,0`, and `full_attention_interval = 4`. The recurrent (gated delta net) layers keep a
fixed-size state and are skipped by the KV cache — visible at load as
`llama_memory_recurrent: layer 3: skipped`. So only **16 of 64 layers carry KV**:

```
16 layers x 4 kv_heads x (256 x bK + 256 x bV)
bK(q8_0) = 34/32 = 1.0625   bV(q4_0) = 18/32 = 0.5625
= 16 x 4 x (272 + 144) = 26,624 B/token
```

That is byte-identical to the BC-250 measurement — same shape (16 KV layers x 4 heads x 256),
different model name. A coincidence worth knowing: the numbers transfer across models here
only because the KV geometry matches.

## Measured cost on the XTX

Multi-turn, one growing conversation, 8 turns, depth 11,124 → 20,841 tokens, sampled every
2 s. Host RSS from the container's init PID; VRAM from `mem_info_vram_used`.

| | RSS start | RSS end | growth | VRAM |
|---|---|---|---|---|
| **`--ctx-checkpoints 32`** (default) | 1,517 MiB | **5,178 MiB** | **+3,661 MiB** | 22,991 → 23,087 **flat** |
| **`--ctx-checkpoints 0`** | 1,515 MiB | **1,796 MiB** | +281 MiB | flat |

**Attribution: 3,382 MiB at depth 20,841, entirely host RAM, VRAM unmoved.** Exactly the
signature the report describes. RSS grew a constant ~455 MiB per turn while depth grew
~1,390 tokens per turn — i.e. one full checkpoint retained per turn, not one per 8,192-token
`--checkpoint-min-step`. **`--checkpoint-min-step` does not bound this live set; the count
does.**

Per-token, from the eight retained depths (sum 127,869 tokens):

```
3,382 MiB / 127,869 tok = 27,734 B/token
                          = 26,624 target + ~1,110 draft
```

The draft term is ~1.1 KB/token here, not the 4,096 B/token the BC-250 measured — different
MTP geometry. Use 27,734 B/token for this config.

## The number for 128k

One checkpoint at full 131,072-token depth:

```
131,072 x 27,734 B = 3.39 GiB
```

Budget: **MemAvailable 26,779 MiB** with production running (30,973 MiB total; note 2.8 GiB
of swap was already in use before any test).

| `--ctx-checkpoints` | worst case @128k | left of 26.8 GiB | @32k | @20k |
|---|---|---|---|---|
| 1 | 3.4 GiB | 23.3 | 0.85 | 0.53 |
| 2 | 6.8 GiB | 19.8 | 1.7 | 1.1 |
| **4** | **13.5 GiB** | **12.6** | 3.4 | 2.1 |
| 6 | 20.3 GiB | 5.8 | 5.1 | 3.2 |
| 8 | 27.1 GiB | **−0.9 (OOM)** | 6.8 | 4.2 |
| 16 | 54.2 GiB | OOM | 13.5 | 8.5 |
| **32 (current default)** | **108.3 GiB** | **OOM by 80 GiB** | **27.1 (OOM)** | 16.9 |

**Answer: 4 checkpoints at ctx 131072.** 6 also fits but leaves only 5.8 GiB for the 8 GiB
`--cache-ram` default plus the OS — too tight. 8 already exceeds available memory at full
depth.

**Production currently runs the default 32 and does not set the variable**, so it is exposed:
a conversation reaching ~32k would need 27 GiB and OOM, and a 128k conversation would need
108 GiB. Real agent tasks peaked at 20,579 tokens (report #2), which costs ~16.9 GiB at 32
checkpoints — it fits, but it is most of the box, and combined with the 8 GiB prompt cache it
is one deeper turn away from swapping.

## Why not just set 0

BC-250 measured ~18 % decode loss with checkpoints off (15.0 vs 18.3 t/s), because they are
the rollback fast path for a context that cannot remove a partial sequence — which is exactly
our `FULL` type. Turning them off trades a memory hazard for a throughput loss. 4 keeps the
fast path while capping the worst case at half of available RAM.

## Recommendation

```yaml
- LLAMA_ARG_CTX_CHECKPOINTS=4
```

Optionally also trim `--cache-ram` from its 8192 default to 2048, which would make 6
checkpoints safe at 128k and still leave ~5 GiB spare. Without that trim, stay at 4.

**Ask before applying to production** — this is a compose change on `llm_backends`, and the
honest tradeoff is rollback granularity (4 recovery points instead of 32) against ~14 GiB of
worst-case headroom.

## Honest boundaries

1. **One config, one model.** The 27,734 B/token figure is for this KV geometry
   (16 KV layers, 4 heads, 256/256). A different model changes it linearly.
2. **Worst case is `count x max_depth`**, which assumes every retained checkpoint sits at the
   deepest point. The measured distribution (one per turn, retained) makes that plausible but
   it is an upper bound; real usage sits lower, as the 20,841-token run showed (8 checkpoints,
   not 32, because only 8 turns happened).
3. **I did not run to 128k.** Extrapolation is from the measured per-token rate at 20.8k. The
   linear model is well supported (constant ~455 MiB/turn, VRAM flat) but not verified at 128k.
4. **`--cache-ram` was 0 in the A/B**, so the 8 GiB prompt cache is *additional* host memory in
   production and is not included in the "left over" column beyond being mentioned.
5. **Swap was already 2.8 GiB used before testing** — the box is not starting from a clean
   slate, which makes OOM margins worse than the arithmetic suggests.

## Artifacts

`/models/ckpt/` on `.101`: `mt.log`, `mt32.json`, `mt0.json`, `measure.py`, `multiturn.py`,
`run_mt.sh`, `ckpt.log`.
