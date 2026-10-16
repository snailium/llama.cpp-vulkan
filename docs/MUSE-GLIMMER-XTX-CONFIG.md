# Muse-Glimmer-30B — candidate config for the 7900 XTX (Vulkan)

**Status: CANDIDATE, not yet run.** Derived by diffing our Qwen3.8-27B production config
against Meta's official guidance, and changing only what the official README requires.
**Nothing here is measured on our hardware.**

## Sourcing rule (this model)

GGUF precedence for Muse-Glimmer, applied in order, stopping at the first that exists:

1. **`meta-models/Muse-Glimmer-30B-GGUF`** — the author's repo. **This is what we use.**
2. a ggml-org GGUF — none exists for this model.
3. `unsloth/Muse-Glimmer-30B-GGUF` — community; **last resort only.**

Community quants are not interchangeable with the author's: they can differ in chat
template, stop tokens, quant recipe, and they may ship no matching companion files
(`mmproj`, drafter). Debugging "the model behaves badly" against a community quant can mean
debugging the quantizer instead of the backend. Companion artifacts must come from the
**same source** as the text weights.

## Artifacts (all from the official repo)

| File | Size | Notes |
|---|---|---|
| `Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf` | 15.61 GiB | text — Meta: *"start here, fits 24 GB VRAM"* |
| `mmproj-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.30 GiB | perception encoder, required for images |
| `dflash-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.52 GiB | DFlash drafter — **phase 2**, not first run |

Total for the recommended first configuration: **~16.9 GiB**. With the drafter: ~18.4 GiB.

## Config diff vs Qwen3.8-27B production

Read this table as "what changes and why". Everything not listed stays as-is.

| Knob | Qwen (prod) | Muse candidate | Why |
|---|---|---|---|
| `MODEL` | `qwen3.8-27b/Qwen3.8-27B-Q4_K_M.gguf` | `muse-glimmer/Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf` | 17GB build is the 24 GB target |
| `MMPROJ` | `qwen3.8-27b/mmproj-Qwen3.8-27B-Q8_0.gguf` | `muse-glimmer/mmproj-Muse-Glimmer-30B-Q4_K_M.gguf` | same-source companion |
| **`JINJA`** | *(unset)* | **`1`** | **required** — template is embedded in the GGUF; without it `llama-mtmd-cli` aborts |
| `TEMP` | `0.7` | **`1.0`** | Meta's stated default |
| `TOP_P` | `0.80` | **`0.95`** | Meta's stated default |
| `TOP_K` | `20` | **`64`** | Meta's stated default |
| `MIN_P` | `0.0` | `0.0` | keep |
| penalties | `1.5 / 0.0 / 1.0` | **same** | Meta states no penalty defaults; keep ours |
| `CACHE_TYPE_K/V` | `q8_0 / q4_0` | **`q8_0 / q8_0`** | KV is cheap here (2 KV heads + SWA); q4_0 buys nothing |
| `CTX_SIZE` | `131072` | `131072` | model's trained max is 131072 |
| `N_PARALLEL` | `1` | **`1` (must stay)** | `-c` is divided by `-np`; at `-np 1` the slot really gets 131072 |
| `REASONING` | `off` | **remove it** | **no effect on Muse** — the template opens the thinking channel unconditionally |
| reasoning control | — | **`REASONING_EFFORT=low`** | this is the real lever (`--reasoning-effort`); template var is `reasoning_strength` |
| `SPEC_TYPE` | `draft-mtp` | **phase 2: `draft-dflash`** | different drafter type |
| `SPEC_DRAFT_MODEL` | `mtp-…-Q4_0.gguf` | **phase 2: `dflash-…-Q4_K_M.gguf`** | official drafter |
| `SPEC_DRAFT_N_MAX` | `4` | **phase 2: `2`** | B70 DFlash data favoured small windows; unverified on Vulkan |
| `IMAGE_MIN_TOKENS` | `1024` | unknown — **omit initially** | Qwen-specific tuning; no Muse equivalent published |
| `CHAT_TEMPLATE_KWARGS` | `{"enable_thinking":false,…}` | **remove** | Qwen-specific; Muse ignores thinking flags |
| `DEVICE` / `N_GPU_LAYERS` / `FLASH_ATTN` / `KV_OFFLOAD` / `HOST` / `PORT` | `Vulkan0 / 999 / on / 1 / …` | **same** | unchanged |
| `VK_DRIVER_FILES` | `radeon_icd.json` | **same** | mixed Intel+AMD host |

## Candidate launch (phase 1 — text + vision, no drafter)

Expressed in the env-var form our production stack uses, so it can drop straight into a
Portainer stack. `--reasoning-budget` has **no env var** and is therefore the one CLI arg.

```yaml
LLAMA_ARG_MODEL=/models/muse-glimmer/Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf
LLAMA_ARG_MMPROJ=/models/muse-glimmer/mmproj-Muse-Glimmer-30B-Q4_K_M.gguf
LLAMA_ARG_JINJA=1
LLAMA_ARG_DEVICE=Vulkan0
LLAMA_ARG_N_GPU_LAYERS=999
LLAMA_ARG_CTX_SIZE=131072
LLAMA_ARG_N_PARALLEL=1
LLAMA_ARG_CACHE_TYPE_K=q8_0
LLAMA_ARG_CACHE_TYPE_V=q8_0
LLAMA_ARG_FLASH_ATTN=on
LLAMA_ARG_KV_OFFLOAD=1
LLAMA_ARG_REASONING_EFFORT=low
LLAMA_ARG_TEMPERATURE=1.0
LLAMA_ARG_TOP_P=0.95
LLAMA_ARG_TOP_K=64
LLAMA_ARG_MIN_P=0.0
LLAMA_ARG_PRESENCE_PENALTY=1.5
LLAMA_ARG_FREQUENCY_PENALTY=0.0
LLAMA_ARG_REPEAT_PENALTY=1.0
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=8080
# no LLAMA_ARG_REASONING   -> it does nothing for this model
# no LLAMA_ARG_CHAT_TEMPLATE_KWARGS -> Qwen-specific
```

Phase 2 adds the drafter:

```
LLAMA_ARG_SPEC_TYPE=draft-dflash
LLAMA_ARG_SPEC_DRAFT_MODEL=/models/muse-glimmer/dflash-Muse-Glimmer-30B-Q4_K_M.gguf
LLAMA_ARG_SPEC_DRAFT_N_MAX=2
LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1
LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q8_0
LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q8_0
```

## VRAM budget

Against the XTX's measured 24560 MiB. Meta's GB figures converted to MiB:

| Configuration | Meta | = MiB | Headroom |
|---|---|---|---|
| **`17gb` + vision (phase 1)** | ~19 GB | 18120 | **6440** |
| `17gb` + vision + drafter (phase 2) | ~20 GB | 19073 | 5487 |
| `dynamic` + vision + drafter | ~23 GB | 21935 | 2625 ⚠️ |

KV at 131072 with `q8_0`/`q8_0`: **3328 MiB** even if every one of the 52 layers cached the
full context (the pessimistic bound; 39 of 52 are sliding-window-2048, so the real figure is
~871 MiB). `num_key_value_heads = 2`, so KV is genuinely cheap.

**Avoid the `dynamic` build on this card** — 2625 MiB is inside the range where our earlier
ceiling work showed behaviour degrades.

## Operational traps (all from the official README)

1. **`-c` is divided by `-np`.** Meta's own example (`-c 131072 -np 4`) gives each slot only
   32768, and the README itself recommends `-c 524288 -np 4` for a true 131072/slot. We pin
   `N_PARALLEL=1`, so `CTX_SIZE=131072` really is 131072 for the one slot. **Verify
   `n_ctx_slot` in the startup log**, not `-c`.
2. **Never stop on `<|eom|>`.** Stop tokens are `200001` and `200008`; `<|eom|>` is
   end-of-*message* and stopping there collapses parallel tool calling. Only relevant if we
   add custom stop strings.
3. **Reasoning cannot be switched off** — control *how much* via `REASONING_EFFORT`
   (`low`/`medium`/`high`/`xhigh`, template default `high`), or hard-cap with the
   `--reasoning-budget N` CLI arg (no env var exists for it).
4. **Reasoning-out-of-context fails silently**: nothing errors, the request just produces no
   answer. With a reasoning model this reads as a wrong answer, not a failure — relevant to
   any eval we run.
5. A `[spec] failed to measure draft model memory` warning at startup is **harmless**
   (official README).

## Pre-flight checks before declaring it working

- [ ] **`n_ctx_slot` = 131072** in the startup log (not `-c / -np`)
- [ ] offload line names **Vulkan0 / RX 7900 XTX**, not CPU
- [ ] free VRAM after load ≥ ~5000 MiB (the cliff we measured appears below ~300 MiB)
- [ ] `content` and `reasoning_content` are **separate**; `content` must not begin with
      `to=self<|message|>` (that means the build predates the chat parser)
- [ ] one image request actually returns an answer (mmproj wired correctly)
- [ ] build ≥ **b10353** — ours are v0.6.0 and b11541, both far newer

## Open questions / unverified

- **Never run on this card or this backend.** Feasibility is a memory-budget argument.
- **Vulkan + SWA + sparse FA** is an untested combination for us. Muse *is* a sparse-FA
  candidate (SWA on 3 of 4 layers, 39/52 with window 2048) unlike qwen35, and Vulkan has
  had sparse FA since b10982. In-source note: quantized K/V sparse *"only breaks even around
  16x (measured on RDNA3/RDNA4)"* — long prompts only. Disable with
  `GGML_VK_FA_SPARSE_DISABLE=1` if it misbehaves.
- **DFlash on Vulkan is unverified.** Our only DFlash experience is SYCL on the B70.
- `IMAGE_MIN_TOKENS` has no published Muse value; leaving it unset is the honest default.

See also: [`MUSE-GLIMMER-XTX-FEASIBILITY.md`](./MUSE-GLIMMER-XTX-FEASIBILITY.md).
