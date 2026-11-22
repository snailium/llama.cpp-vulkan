# llama.cpp Vulkan Test Report — AMD RX 7900 XTX · `server-dev-m26.2-b12603-20261121-0618`

**Date:** 2026-11-22 · **Host:** home-ai `.101` · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB, NAVI31, RADV)
**Target:** XTX only. The B70 was not tested and not touched (`RestartCount` 0 → 0).

| | |
|---|---|
| Backend image | `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-dev-m26.2-b12603-20261121-0618` |
| Image digest | `sha256:34d5ce3e0d34ef00ed5dc86a0602da0a646c44bdc71b2884c763d83327091496` |
| llama.cpp ref | **b12603** (built 2026-11-21, i.e. after the `v1.0.0` tag `b1b770d90`) |
| Harness | `ghcr.io/snailium/dsh-container/dsh@sha256:8168e37566bccb1603b05bc55b1f0e725ad374a35999131d40212f6a84ab92c1` (dsh 0.2.2-rc.2) |
| Skill sha256 | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Model | `/models/Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-…-Q8_0` (projector on GPU; `MMPROJ_OFFLOAD` deliberately absent) |
| KV | **q8_0 K / q4_0 V** @ ctx 131072 · draft KV q8_0/q4_0 |
| Spec decode | `draft-mtp`, **K = 4** |
| Free VRAM after load | **676 MiB** |
| Sampling | **inherited** — read back from `/props`: temp 0.7, top_p 0.80, top_k 20, min_p 0.0, presence 1.5, frequency 0.0, repeat 1.0 (equals the golden re-read from `docs/GOLDEN-CONFIG.md`) |
| Request fields | only `chat_template_kwargs:{enable_thinking:false}` + `max_tokens:32768` (T1/T2, V1-V3) + `stream:true` (T1/T2) |
| Trim auto-tune | **ON** — `Retuned compaction-basic`; persisted `headroomTokens=9831` (trigger 80 % of window vs stock 37.5 %) |

Harness digest is unchanged from the 2026-11-15 run; the skill file and all three image assets hash-match the skill table.

## Results Summary

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 181.3 | 0.472 | 4,157 | 83.41 | 65.35 | structure correct, ends `</html>` |
| T2 | **PASS** | 32 | 142.3 | 0.359 | 4,316 | 95.47 | 79.73 | well-formed XML, single `<svg>`, `viewBox`, ends `</svg>` |
| A1 | **PASS** | 45,236 ᵀ | 351.5 ᴹ | 2.521 ᴹ (max 33.75) | 4,785 | 45.63 ᴬ | 64.32 ᵂ | H-1/H-2, M-1…M-5, L-1…; spot-checks verified |
| A2 | **PASS** | 8,832 ᵀ | 438.1 ᴹ | 1.337 ᴹ (max 10.79) | 1,220 | 90.17 ᴬ | 64.32 ᵂ | JSON valid, values gathered, **GPU correctly reported absent** |
| A3 | **FAIL** | 236,990 ᵀ | 206.3 ᴹ | 1.007 ᴹ (max 72.23) | 13,788 | 61.81 ᴬ | 64.32 ᵂ | wrong station key → ERA5 fallback → **unit conflation, 14.6 cm vs 258.6 cm** |
| V1 | **PASS** | 3,528 | 545.7 | 6.465 | 849 | 67.74 | 48.87 | every ground-truth field correct |
| V2 | **PASS** | 1,064 | 627.9 | 1.695 | 1,349 | 71.24 | 50.90 | **15/21** labels |
| V3 | **FAIL** | 4,160 | 283.2 | 14.690 | 480 | 65.19 | 46.28 | read **T136** (truth 118S); brand correctly declined |

ᵀ Σ input tokens over all model steps · ᴹ median over steps · ᴬ output tokens ÷ Σ streamed step time · ᵂ weighted over all 120 requests in the server log (22,226 / 34,556 = 64.32 %).

**6 / 8 PASS.**

**A1 review coverage (observation — never gating):**

```
files touched / inventory : 14 / 25  (56 %)
read calls               : 13   (+ bash x5)
missed                   : .dockerignore, .gitignore, LICENSE, bridge_test.go,
                           fakeclient_test.go, go.sum, infer_test.go,
                           scripts/mqtt2ha_sqlite2yaml.py, store_test.go, uniqueid_test.go,
                           yamlstore_test.go
notable                  : all 7 _test.go files skipped again — fifth consecutive run
```

## T2 — PASS this time

b12375 failed T2 on a corrupted closing tag (`</radowGrad>`). b12603 produced a complete, well-formed
document with the same prompt and the same server-side sampling. One sample each way cannot separate
"b12375 shipped a bug that b12603 does not have" from sampling variance at temp 0.7, so this is
recorded as a pass, not as evidence of a fix.

## A3 — FAIL: right method, wrong station key, then a unit conflation

The answer is transparent and reproducible, which is why the failure is diagnosable:

1. It chose **ECCC station 4337 / Climate ID 6106000** for YOW. That key returns records with **every
   observation field `null`** — which is exactly what it reports seeing.
2. The correct key for this station's live daily data is **`STN_ID 49568`**, which the previous run
   (b12375) found and which returns 380 populated records. So the nulls were a consequence of its own
   station identifier, not of the API.
3. It then fell back to **Open-Meteo Archive (ERA5 reanalysis)** and summed `snowfall_sum` for
   2025-11-01 → 2026-11-22, getting **145.7 mm**, reported as **"≈ 14.6 cm"**.

The fallback source is legitimate — the task says no source is privileged. The error is the **unit**:
it describes the variable as "mm, 以液态水当量计" (liquid water equivalent) and then divides by 10 as
if it were snow depth in mm. Water equivalent and snow depth are not interchangeable; and the result,
14.6 cm for a full Ottawa winter, is ~18x below the station truth.

For reference, the station observation for the same window is **258.6 cm** (independently recomputed
from the ECCC daily records, and matching the monthly figures recorded when this task last produced
correct output). Its own "largest single day 9.1 mm / 0.91 cm" is also implausible — Ottawa's largest
snow day that winter was 21 cm.

Failures on the criterion: a unit error, and a total that is not the quantity asked for.

## A2 — PASS, cleanly

This time it reported `{"detected": false, "note": "No GPU devices found. lspci unavailable in
container environment, no NVIDIA driver or /dev/dri present."}` — which is the correct answer for this
container. CPU (Ryzen 7 5700X), memory (60 GiB), disk and OS (Debian 12) all match the machine that
ran the container, gathered with 5 shell calls (`lscpu`, `free`, `df`, `lspci`, `ls /dev`).

Note the contrast with the previous run, which found the PCI devices through sysfs and then invented
the product names. Both are "gathered", but only this one is also accurate.

## V3 — FAIL on the load index, with one genuine improvement

- Size **255/70R18** correct; none of the prompt's decoys (`245/60R17`, `104T`) were copied.
- Brand: **correctly declined** — "照片中未清晰显示具体的品牌名称". Every previous run asserted a brand
  (BFGoodrich, COOPER); this one did not.
- M+S and the three-peak mountain snowflake both identified.
- Load/speed index read as **T136** where the truth is **118S**. It also built a story on that reading
  ("temporary spare, 130 km/h limit"), which is the failure mode: an incorrect field elaborated into
  a confident conclusion.

## Stability

| check | result |
|---|---|
| crash signatures (`SIGSEGV` / `device lost` / `ErrorDeviceLost`) | **0** |
| requests served | 120 · max single-request prompt **71,436** tokens |
| weighted draft acceptance | **64.32 %** (22,226 / 34,556) |
| compactions | 0 in A1/A2/A3 |
| `b70-sycl` RestartCount | 0 → **0** |

## Restore

`xtx-vulkan` started, `/health` ok, both workers `ready`, and a **routed request through SMG returned a
real completion**. No circuit-breaker reset was needed.

The routed reply came back with `system_fingerprint` `b0-unknown`, which is the SMG fallback value (the
request was served by the B70 worker, whose SYCL build reports similarly); the XTX's own direct
identity is `b1-b1b770d` = **v1.0.0**. Both workers were `ready` at the time.

## Verdict

**Do not promote b12603 on this battery.** 6/8, and both failures are model-level and reproducible in
kind from the previous runs:

- **A3** — station-key selection plus a water-equivalent/snow-depth conflation. Nothing here is a
  backend property; a different GPU would produce the same reasoning error.
- **V3** — 113S/T136-class load-index misreads, mitigated this time by correctly declining the brand.

The battery is also structurally blind to what changed in this build. b12375 → b12603 adds 20 Vulkan
commits, and the ones that matter to this configuration are all **throughput** changes: RDNA3/4 prompt-
processing Flash Attention (`d8f30a5b6`), narrow-N matmul tiles (`d20426bbb`), stream-k matmul
(`573aa89de`), MMQ mixed-signedness integer dots (`7a4117eef`), and a chunked GATED_DELTA_NET
(`16f80bd0c`) whose RDNA3 gate requires **n_tokens >= 4096 per graph** — which the default ubatch does
not reach, so it is inert for us as shipped (`GGML_VK_DISABLE_GDN_CHUNKED=1` measured identical:
801.15 vs 800.03 t/s on a 6,669-token prompt).

The T1/T2 prompts are 32-43 tokens, so they cannot exercise any of that. **If this build is a promote
candidate, the decision has to come from a decode/prefill comparison against the running v1.0.0
container, not from this battery.**
