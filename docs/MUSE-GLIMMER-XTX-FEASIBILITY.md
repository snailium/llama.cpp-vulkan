# Muse-Glimmer-30B on the 7900 XTX (Vulkan) — feasibility

**Date:** 2026-10-13 · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB, NAVI31 / RDNA3)
**Backend:** llama.cpp Vulkan / RADV (Mesa 26.2.3) · **Verdict: FEASIBLE — all three
official configurations fit, including vision + drafter.**

## Artifact sourcing (precedence: meta official → ggml → unsloth)

Use the **official Meta repo**. It exists and supersedes the unsloth build we had been
using for the B70 work:

| Source | Repo | Use? |
|---|---|---|
| **meta official** | [`meta-models/Muse-Glimmer-30B-GGUF`](https://huggingface.co/meta-models/Muse-Glimmer-30B-GGUF) | **YES** — 785,708 downloads, `base_model:meta-models/Muse-Glimmer-30B`, apache-2.0, last modified 2026-08-18 |
| ggml | (no `ggml-org` GGUF for this model exists) | — |
| unsloth | [`unsloth/Muse-Glimmer-30B-GGUF`](https://huggingface.co/unsloth/Muse-Glimmer-30B-GGUF) | only if the official repo lacked a needed quant |

Official repo contents (exactly 4 GGUFs, no BF16 published — use the base repo for full
precision):

| File | Size | Purpose |
|---|---|---|
| `Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf` | 15.61 GiB | text — *"start here, fits 24 GB VRAM"* |
| `Muse-Glimmer-30B-KQuant-Dynamic-Q4_K_XL.gguf` | 18.30 GiB | text, higher quality, *"for 32 GB VRAM"* |
| `mmproj-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.30 GiB | perception encoder — required for images |
| `dflash-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.52 GiB | DFlash drafter — optional |

## Memory: everything fits

Meta publishes a memory table keyed to exactly our envelope. Converted to MiB against the
XTX's measured 24560 MiB:

| Build | Meta's figure | = MiB | Headroom on XTX |
|---|---|---|---|
| `17gb` text only | ~17 GB | 16212 | 8348 |
| `17gb` + vision | ~19 GB | 18120 | 6440 |
| **`17gb` + vision + drafter** | **~20 GB** | **19073** | **5487** |
| `dynamic` text only | ~20 GB | 19073 | 5487 |
| `dynamic` + vision | ~22 GB | 20981 | 3579 |
| `dynamic` + vision + drafter | ~23 GB | 21935 | 2625 |

The model card states the intent directly: *"This leaves enough headroom for the model's
KV cache, the perception encoder for image understanding, and the speculative decoding
drafter to run simultaneously within a 24 GB or 32 GB envelope."* The XTX is the 24 GB
target.

**KV cache is genuinely cheap**, which is the reason this works at 24 GB. From the base
`config.json`: `num_key_value_heads = 2` (GQA 16:1 against 32 query heads) and
`sliding_window = 2048` on 39 of 52 layers. Measured against our own numbers:

| ctx | KV (q8_0, all 52 layers at full ctx — pessimistic) | weights + KV |
|---|---|---|
| 32768 | 832 MiB | 18865 MiB |
| 65536 | 1664 MiB | 19697 MiB |
| **131072** | **3328 MiB** | **21361 MiB** |

Even ignoring the sliding-window saving entirely, 128K + q8_0 KV leaves **3.2 GiB** on the
card. With the SWA cap applied it is ~871 MiB, leaving ~5.5 GiB.

## Backend support: present, and no version floor problem

| Requirement | Status |
|---|---|
| `LLM_ARCH_MUSE_GLIMMER` | present |
| `LLM_ARCH_DFLASH` (drafter) | present |
| Version floor | README requires **≥ b10353**. Production `xtx-vulkan` is **v0.6.0** (`d812350`); issue #11's build is **b11541**. Both are ~1200 builds newer. |

**Bonus: Muse-Glimmer is a sparse-FA candidate, and Vulkan already has it.** Our tracking
ledger records that sparse FA is dead code for qwen35 because that model declares no
sliding-window attention. Muse-Glimmer is the opposite — SWA on 3 of every 4 layers — which
is exactly the precondition `use_sparse` needs:

```cpp
const int64_t min_ratio = tuning_params.path == FA_COOPMAT2 ? 4 : (kv_f16 ? 2 : 16);
const bool use_sparse = !disable_sparse && n_kv_max > 0 && mask &&
                        max_bias == 0.0f && logit_softcap == 0.0f && ...
```

Vulkan sparse FA merged as **b10982** (`fc82583e6`), extended to quantized K/V by
`b3daa077a` and to coopmat2 by `dac308739` — all **already in our b11541 image**. The
in-source note is measured on our silicon: *"With quantized K/V, sparse only breaks even
around 16x (measured on RDNA3/RDNA4)."* So the payoff appears at long prompts; it is a
watch item, not a reason by itself.

Escape hatch if it misbehaves: `GGML_VK_FA_SPARSE_DISABLE=1`.

## Official invocation, adapted to our golden conventions

Meta's command:

```bash
llama-server \
    -m       Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf \
    --mmproj mmproj-Muse-Glimmer-30B-Q4_K_M.gguf \
    -a muse-glimmer-30B \
    -ngl 99 -c 131072 -np 4 \
    --host 127.0.0.1 --port 8080 \
    --jinja \
    --temp 1.0 --top-p 0.95 --top-k 64
```

Add the drafter with `-md dflash-Muse-Glimmer-30B-Q4_K_M.gguf -ngld 99`.

**Differences from our Qwen golden that must not be carried over silently:**

| Knob | Our Qwen golden | Muse-Glimmer | Why |
|---|---|---|---|
| `--jinja` | not used | **required** | template is embedded in the GGUF; without it `llama-mtmd-cli` aborts |
| sampling | temp 0.7 / top_p 0.80 / top_k 20 | **temp 1.0 / top_p 0.95 / top_k 64** | the model's own defaults |
| reasoning | `--reasoning off` works | **no effect** | template opens the thinking channel unconditionally |
| KV | q4_0 (XTX) | q8_0 is affordable here | KV is cheap enough that q4_0 buys nothing |
| ICD | `radeon_icd.json` | same | mixed Intel+AMD host |

**Three operational traps, all from the official README:**

1. **`c` is split across `-np`.** A request gets `-c / -np`. The README's own `-c 131072
   -np 4` gives each slot only **32768** — it recommends `-c 524288 -np 4` for full
   131072 per slot. With `--parallel 1` (our convention) `-c 131072` *is* 131072 per slot,
   so pinning `-np 1` avoids the trap entirely.
2. **Never stop on `<|eom|>`.** Stop tokens are `200001` and `200008`; `<|eom|>` is
   end-of-*message* and stopping on it collapses parallel tool calling.
3. **Reasoning length is controlled via `reasoning_strength`** (`low`/`medium`/`high`/
   `xhigh`, default `high`), or capped with `--reasoning-budget N` — not with `--reasoning`.

## Risks and unknowns

| Risk | Assessment |
|---|---|
| **It has never been run on this card or this backend** | All figures above are Meta's published numbers plus my arithmetic. **Nothing here is measured on our hardware.** Feasibility is a budget argument, not a result. |
| Vulkan + SWA + sparse FA interaction | Untested combination for us. The 16x break-even is a measured note, but not on our model. |
| DFlash on Vulkan | `draft-dflash` is a first-class spec type and the arch is supported, but our only DFlash experience is **SYCL on the B70** (26.8 t/s p512). Treat Vulkan DFlash as unverified. |
| Reasoning model on an agent route | Thinking cannot be disabled; on agent workloads this costs tokens and context. Needs `reasoning_strength` tuning, not a flag. |
| 24 GB is genuinely tight for `dynamic` + vision + drafter | 2625 MiB headroom is inside the range where our XTX cliff work showed behaviour degrades. Prefer the `17gb` build. |

## Recommendation

**Feasible. Start with the `17gb` build + vision, no drafter**, then add DFlash as a second
step. Rationale: that combination is the one Meta explicitly sizes for 24 GB and it keeps
~5.5 GiB of headroom, which is comfortably away from the free-VRAM cliff we measured for
this card (the cliff appeared below ~0.3 GiB free).

Suggested first step is a **smoke test, not a battery**: load it, confirm the offload line
and `n_ctx_slot`, and confirm `content` vs `reasoning_content` split correctly. If the load
log shows healthy VRAM and the model answers, it is worth a full suite.

Download (~18.4 GiB for `17gb` + mmproj, or ~19.9 GiB with the drafter) to `.101` — 298 GB
free — but **do not start it while `xtx-vulkan` is serving**: the card is single-tenant and
currently has only 716 MiB free.
