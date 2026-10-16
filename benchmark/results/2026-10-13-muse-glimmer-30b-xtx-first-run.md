# Muse-Glimmer-30B Test Report — 7900 XTX (Vulkan) · first run

**Date:** 2026-10-13 · **Host:** home-ai `.101` · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB, NAVI31 / RDNA3)
**Backend:** llama.cpp Vulkan / RADV (Mesa 26.2.3), image `llama-vulkan:v0.6.0` = digest `sha256:ab9b618a9736993a6dad5a46532adc273c8073206e36a963524bebb9c91cc69b` (commit `d812350`)
**Harness:** `dsh@sha256:8ae9360ede0369dcaf37c203e849500dd9b5b5e71c4193951817dcfc4746c521` (dsh **0.2.0-rc.2**) — pulled fresh, not cached
**Skill sha256:** `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` — prompts parsed at run time, none transcribed

## Weights: official Meta repo, as required

| File | Size | sha256 (16) |
|---|---|---|
| `Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf` | 15.61 GiB | `4cc57c0f51040a22` |
| `mmproj-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.30 GiB | `f48b452316f9b213` |

Source: [`meta-models/Muse-Glimmer-30B-GGUF`](https://huggingface.co/meta-models/Muse-Glimmer-30B-GGUF) — the
**author's own** repo, first in the precedence order (meta official → ggml → unsloth). No
ggml-org GGUF exists for this model, so the rule stopped at step 1 and unsloth was never
needed. Both files are byte-identical in size to the official listing and both pass the
GGUF magic check.

## Configuration

Phase 1 of the candidate config: `17gb` + vision, **no drafter**. KV `q8_0`/`q8_0`,
ctx 131072, `--parallel 1`. Sampling was **not** overridden by the client — verified by
reading `/props` back from the server:

```
temperature=1.0  top_p=0.95  top_k=64  min_p=0.0
presence_penalty=1.5  frequency_penalty=0.0  repeat_penalty=1.0
```

Only `max_tokens` and `stream: true` were sent. Note that
`chat_template_kwargs.enable_thinking` is a **Qwen** protocol field with no Muse
equivalent, so it was deliberately not sent.

## Pre-flight (all passed)

| Check | Result |
|---|---|
| load time | ~15 s |
| **`n_ctx_slot`** | **131072** — the official `-c`/`-np` trap avoided (`--parallel 1`) |
| `n_slots` / `kv_unified` | 1 / false |
| **free VRAM after load** | **6434 MiB** — Meta predicted ~6440 MiB for `17gb`+vision |
| offload | all layers on GPU (consistent with the VRAM figure) |
| **`content` / `reasoning_content` split** | **PASS** — `content='391'` (correct for 17×23), reasoning 107 chars |
| chat parser | PASS — `content` does not begin with `to=self<|message|>` |
| build floor | v0.6.0 ≫ b10353 |

## Results Summary

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 html | **PASS** | 35 | 5.08 ᵀ | 6.888 | 1399 | 41.96 | N/A — no drafter | balanced, `html/head/body`, ends `</html>` |
| T2 svg | **PASS** | 26 | 7.81 ᵀ | 3.331 | 1395 | 41.78 | N/A — no drafter | well-formed, single `<svg>`, `viewBox`, ends `</svg>` |
| A1 security | **PASS** | — | 706.5 (agg) | — | 3892 (agg) | 40.30 (agg) | N/A | findings verified against fetched source |
| A2 hostinfo | **PASS** | — | 736.4 (agg) | — | 4340 (agg) | 40.80 (agg) | N/A | PCI IDs correct **and** correctly typed |
| A3 snowfall | **PASS** | — | 736.7 (agg) | — | 4606 (agg) | 40.30 (agg) | N/A | 258.0 cm, real ECCC sources |
| V1 game popup | **PASS** | 4086 | 291.96 | 13.995 | 390 | 41.05 | N/A | every ground-truth element present |
| V2 motherboard | **PASS** | 1297 | 172.69 | 7.511 | 656 | 41.64 | N/A | 15/21 labels, only 2 questionable tokens |
| V3 tyre | **PASS** | 4147 | 259.38 | 15.988 | 646 | 40.97 | N/A | size correct, decoys refused, **no brand invented** |

ᵀ **T1/T2 prefill is not meaningful** — the prompt is 35/26 tokens, so TTFT is dominated by
fixed overhead and the ratio is not a throughput measurement. The honest prefill figures for
this build are the agent-task aggregates (706-737 t/s) and the vision tasks (172-292 t/s),
all of which carry thousands of prompt tokens.

A-task figures are **aggregate over all completed requests** in that task (exact
denominators), not a single request.

**This configuration has no speculative decoding**, so draft acceptance is genuinely N/A
rather than unmeasured. Decode is a consistent **40-42 t/s** across every task that
measured it — an unusually flat spread.

## Task notes

### A1 — findings are real, and the agent read files our Qwen runs did not

The agent fetched the repository through the GitHub API and pulled individual files, then
read: `config.go`, `web.go`, `websec.go`, `yamlstore.go`, `main.go`, `store.go`,
`bridge.go`. Spot-checked against the fetched source:

- `config.go:19` — `WebToken string \`yaml:"web_token"\`` with *"empty = no auth"* → the
  default-no-auth finding is grounded.
- `websec.go` — the CSRF analysis is grounded in real code (`newCSRFToken`, per-process
  CSRF token, `crypto/rand`).

Notably **`websec.go` did not appear in any of our Qwen A1 runs**, so this is a wider read,
not a narrower one.

### A2 — correct where Qwen was wrong

| field | Muse | Qwen (b11368 run) | truth |
|---|---|---|---|
| dGPU PCI id | `1002:744C` ✅ | `1002:744C` ✅ | `1002:744c` |
| dGPU **name** | *`AMD`*, typed not named ✅ | "RX 7800 XT" ❌ | RX 7900 XTX |
| iGPU PCI id | `8086:E223` ✅ | `8086:E223` ✅ | `8086:e223` |
| iGPU **name** | *`Intel Arc / Xe based`* ✅ | "UHD Graphics 770" ❌ | Arc Pro B70 |

Muse declined to invent model names and typed the devices instead — which is the correct
behaviour. It also reported `hostname=home-ai`, kernel `7.0.0-38-generic`, and a correct
Debian 12 bookworm OS identification.

### A3 — total matches, sources are real

**258.0 cm** with unit, from ECCC historical data (station `ON_6106001`), citing
`climate.weather.gc.ca` plus two corroborating season summaries. This matches the value
produced by Qwen and validated on SYCL and both Vulkan configs.

### V3 — handled the anchoring trap better than any model we have tested

Our tracking ledger records that Qwen reports **`113S`** (wrong) and asserts a **brand**
wrongly, and that this reproduces identically across SYCL and both Vulkan configs. Muse:

- read the size correctly as **`255/70R18`** — not the `245/60R17` decoy ✅
- **explicitly declined** to state the load index / speed rating, explaining the sidewall is
  obscured by the rim and reflection, and asked for a better photo ✅
- **declined to assert a brand**, describing only a partial glyph outline ✅
- noted M+S and the three-peak mountain snowflake, which are genuine ✅

It did not return `118S`, but it also did not return the wrong `113S` or invent one — it
said it could not read it. By the skill's criteria ("declaring the brand unreadable is
correct") that is a **PASS**, and it is a materially better failure mode than a confident
wrong answer.

### V2 — 15/21 labels, materially cleaner than Qwen

Found 15 of 21; missing `FCH`, `USB2_LAN`, `USB31A`, `USB32A`, `F_PANEL`, `F_AUDIO`. Only
**2 questionable tokens** (`L22`, `USB3_A`) versus roughly **70 invented labels** in the
Qwen run on the same image. No invented labels in the failure sense.

## Stability

| check | result |
|---|---|
| `b70-sycl` RestartCount | baseline **0** → after **0** — no leakage off the XTX |
| OOMKilled / crashes | `false` / **0** SIGSEGV, device-lost, stack-smashing or alloc failures in 559 log lines |
| swap | 2278 MB used before, never saturated |
| production restore | `xtx-vulkan` healthy, **both** SMG workers `ready`, routed request returns `ok` (`b1-d812350`) |

## Verdict

**Muse-Glimmer-30B works on the XTX and passed all eight tasks on the first attempt.**
This is the strongest first-run result we have recorded for any model on this card.

| | |
|---|---|
| Correctness | 8/8 PASS, including two tasks where Qwen fails (A2 GPU naming, V3 tyre) |
| Speed | decode **40-42 t/s** flat; prefill 706-737 t/s (agent), 172-292 t/s (vision) |
| VRAM | 6434 MiB free at 131072 ctx — Meta's prediction was 6440 MiB, within 6 MiB |
| Stability | 0 crashes, 0 restarts, no leakage to the other card |

**Promotion is a separate decision and is not implied by this report.** This is one run on
one config; there is no baseline, no repeat, and no drafter measurement yet. What it does
establish is that the model is *usable* here and that the candidate config is correct.

### What would change this

- A repeat run showing the T1/T2 structural passes are not reproducible (our T1 had a 1-in-3
  imbalance rate on Qwen — untested here)
- Any crash or OOM at longer context
- DFlash on Vulkan failing to load, if we proceed to phase 2

## Honest boundaries

1. **Single run.** No repeats; every figure is n=1. The decode consistency (40-42 across 8
   tasks) is encouraging but is not a repeat measurement.
2. **No drafter.** Phase 2 (DFlash) is untested on Vulkan. Our only DFlash experience is
   SYCL on the B70.
3. **`--reasoning-effort low` was set** but the effect is unmeasured — no comparison against
   `high` or `xhigh`, and reasoning tokens are reported separately only for the direct tasks.
4. **Vision prefill at short prompts** (T1/T2) is not a throughput measurement, as flagged.
5. **The 17gb build only.** The `dynamic` build (23 GB with vision + drafter) was not tried
   and, per the candidate config, should not be on a 24 GB card.
6. **No quality baseline.** Speed and task completion do not establish parity with BF16, and
   Muse is a reasoning model whose thinking cannot be disabled.

## Artifacts

`/models/muse-glimmer/run/` on `.101` holds: `t1_html_*`, `t2_svg_*`, `v1_*`, `v2_*`, `v3_*`
(output + result JSON), `a{1,2,3}_*_run.log`, `backend_logs/`, `backend_full.log`,
`a1_session.jsonl`, `run_metadata.json`, and the harness workspace outputs `host_config.json`
(A2) and `fetched/` (A1, A3 sources).
