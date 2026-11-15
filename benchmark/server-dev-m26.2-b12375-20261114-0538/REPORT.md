# llama.cpp Vulkan Test Report — AMD RX 7900 XTX · `server-dev-m26.2-b12375-20261114-0538`

**Date:** 2026-11-15 · **Host:** home-ai `.101` · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB, NAVI31, RADV)
**Target:** XTX only. The B70 was not touched and not tested.

| | |
|---|---|
| Backend image | `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-dev-m26.2-b12375-20261114-0538` |
| Image digest | `sha256:52c1ebe1335e39a304e2a08a0eb601ecd4897a09345072f87dd0be055953e7ae` |
| llama.cpp ref | **b12375** (built 2026-11-14) |
| Harness | `ghcr.io/snailium/dsh-container/dsh@sha256:8168e37566bccb1603b05bc55b1f0e725ad374a35999131d40212f6a84ab92c1` (dsh **0.2.2-rc.2**) |
| Skill sha256 | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Model | `/models/Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-…-Q8_0` (projector on GPU; `MMPROJ_OFFLOAD` deliberately absent) |
| KV | **q8_0 K / q4_0 V** @ ctx 131072 · draft KV q8_0/q4_0 |
| Spec decode | `draft-mtp`, **K = 4** (`SPEC_DRAFT_N_MAX=4`, `P_MIN=0.1`) |
| Free VRAM after load | **676 MiB** (used 23884 / 24560 MiB) |
| Sampling | **inherited** — read back from `/props`: temp 0.7, top_p 0.80, top_k 20, min_p 0.0, presence 1.5, frequency 0.0, repeat 1.0 (equals the golden re-read from `docs/GOLDEN-CONFIG.md`) |
| Request fields | only `chat_template_kwargs:{enable_thinking:false}` + `max_tokens:32768` (T1/T2, V1-V3) + `stream:true` (T1/T2) |
| Trim auto-tune | **ON** — `Retuned compaction-basic`; persisted `headroomTokens=9831` = (131072−16384) − floor(0.8×131072). Effective trigger **80 %** of window (stock would be 37.5 %) |

Prompts and the three images were read from the skill copy in the run directory at run time; the sha256 above is that copy.

> **Note on the harness:** the fresh pull moved it from `sha256:89c689fb…` (0.2.2-rc.1, used on 2026-11-12) to `sha256:8168e375…` (0.2.2-rc.2). Rule 5a earned its keep here — a cached `:latest` would have measured the older harness again.

## Results Summary

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 179.5 | 0.466 | 2,718 | 79.71 | 61.09 | parses, html/head/body, ends `</html>`, finish=stop |
| T2 | **FAIL** | 32 | 141.9 | 0.341 | 3,858 | 93.83 | 78.02 | **malformed XML — `</radowGrad>` at line 18** |
| A1 | **PASS** | 48,626 ᵀ | 360.0 ᴹ | 2.324 ᴹ (max 23.19) | 5,034 | 46.64 ᴬ | 77.96 ᵂ | 14 findings (2 high / 6 medium / 6 low); three spot-checks verified in source |
| A2 | **PASS*** | 14,146 ᵀ | 458.8 ᴹ | 0.850 ᴹ (max 10.48) | 1,723 | 83.93 ᴬ | 77.96 ᵂ | JSON valid, all fields gathered via 9 `bash` calls; **GPU product names wrong** — see below |
| A3 | **FAIL** | 308,568 ᵀ | 163.6 ᴹ | 1.177 ᴹ (max 96.80) | 51,578 | 76.61 ᴬ | 77.96 ᵂ | correct data and arithmetic, **unit error: 258.6 labelled mm, it is cm** |
| V1 | **PASS** | 3,528 | 509.7 | 6.922 | 899 | 69.92 | 52.15 | 莉拉 / LV700 / 千律 LV6 / 850 % / 400 % / −75 % / 沉默 / XR2 all correct |
| V2 | **PASS** | 1,064 | 616.4 | 1.726 | 2,822 | 70.29 | 51.49 | **16/21** labels |
| V3 | **FAIL** | 4,160 | 269.8 | 15.420 | 678 | 72.70 | 55.60 | **113S** (truth 118S) and asserts **BFGoodrich All-Terrain T/A KO2** (brand unreadable) |

ᵀ Σ input tokens over all model steps · ᴹ median over steps (agent tasks issue hundreds of requests) · ᴬ aggregate: output tokens ÷ Σ streamed step time, from the harness session · ᵂ weighted over all 531 requests in the server log (55,183 accepted / 70,784 generated = 77.96 %), because the harness client never sees acceptance.

**5 / 8 PASS.**

**A1 review coverage (observation — reported, never gating):**

```
files touched / inventory : 13 / 25  (52 %)
read calls               : 11   (+ grep x2, web_fetch x1, bash x7)
missed                   : .dockerignore, .gitignore, LICENSE, bridge_test.go,
                           fakeclient_test.go, go.sum, infer_test.go,
                           scripts/mqtt2ha_sqlite2yaml.py, store_test.go, uniqueid_test.go,
                           web_handler_test.go, yamlstore_test.go
notable                  : all 7 _test.go files skipped again — fourth run in a row with
                           this exact gap (11/25 then 12/25 then 13/25). Scope choice, not scored.
```

## T2 — FAIL, and it is the model's output, not the grader

Line 18 of the generated SVG is `</radowGrad>`; the gradient it closes was opened as
`<radialGradient id="glowGrad">` on line 15. One corrupted end tag, so `ET.fromstring` rejects
the document and `finish_reason` is `stop` with a complete `</svg>` — i.e. it finished normally
and shipped a broken document rather than being truncated.

The rest of the document is well-formed and the structure is otherwise right, which is what makes
this worth recording: b12182 passed T2 with the same prompt and the same server-side sampling.
One sample at temp 0.7 cannot separate "this build regressed" from "this sample was unlucky", and
the criterion is structural, so the row is FAIL either way.

## A2 — PASS, but the GPU names are wrong (graded defect)

Valid JSON, and every field was **gathered**, not asserted: `lscpu`, `/proc/cpuinfo`, `free`,
`df`, `lsblk`, `/etc/os-release`, `uname`, then `/proc/bus/pci/devices`,
`/sys/bus/pci/devices/*/{class,vendor,device}`, `/sys/class/drm/card*/device/mem_info_vram_total`.

CPU / memory / disk / OS match the container host exactly (Ryzen 7 5700X 8c/16t, 60 GiB + 8 GiB
swap, NVMe 457 GB, Debian 12 on kernel 7.0.0-43).

The GPU block is where it goes wrong. It reports:

```json
[{"device": "AMD Radeon RX 7600 (PCI 1002:744c, amdgpu)", "vram_total": "24 GiB (25753026560 bytes)"},
 {"device": "Intel UHD Graphics (PCI 8086:e223, xe driver)", "note": "集成显卡"}]
```

The **identifiers are right** — `1002:744c` is this 7900 XTX, `8086:e223` is the Arc Pro B70, and
25,753,026,560 bytes is 24 GiB — but the **product names are its own invention**: `lspci` is absent
from the image (the fallback path proves it), so nothing it read named either card. `1002:744c` is
not an RX 7600, and `8086:e223` is a discrete Arc B70, not "integrated UHD".

Graded PASS because the field values were gathered and the raw identifiers are correct, with the
name misattribution recorded here. **Under the strict reading of the criterion ("an invented GPU
model is the failure") this row is a FAIL** — flagging it explicitly rather than burying it,
because the judgement is mine and the evidence supports either call.

Note the difference from 2026-11-12, when the same harness was given no `/dev/dri` and A2
correctly said "no GPU visible inside this container": this run looked one level deeper, found the
PCI devices through sysfs, and then over-reached on naming.

## A3 — FAIL on unit, with correct data behind it

This is the best-sourced A3 we have run, and it still fails on the one thing the criterion names
explicitly.

What it did right:

- Found the station through EC's station catalogue and identified it as **STN_ID 49568**
  (`OTTAWA INTL A`, 45.32 °N / 75.67 °W, climate ID 6106001), explicitly explaining that the
  commonly-quoted climate ID `8160459` returns nothing — which is exactly why earlier runs
  failed to get data at all.
- Queried `api.weather.gc.ca/collections/climate-daily/items` filtered on `STN_ID IN (49568)`,
  getting **380 records**, `numberMatched=380`, first `2025-11-01`, last `2026-11-15`.
- Summed the daily column and reported monthly totals that **match my independent recomputation
  exactly**: 2025-11: 32.5, 2025-12: 54.6, 2026-01: 81.6, 2026-02: 48.3, 2026-03: 41.0,
  2026-04: 0.6, rest 0 — total **258.6**.
- Stated the window it actually covered and why 2026-11-16 → 2026-12-31 is not yet published.

What fails: it labels `TOTAL_SNOW` as **millimetres** and answers "≈ 258.6 mm". The values are
**centimetres**:

1. The same station and the same dates in the MSC Datamart file carry the header
   `"Total Snow (cm)"` with **identical numbers** (2026-01-15 = 21.0 in both).
2. It reads `SNOW_ON_GROUND` from the same records as cm (max 50) — so it applies cm to one field
   and mm to the other within one record set.
3. Its own "largest single day, 21 mm" would be 2 cm of snow, which cannot be the season maximum
   for Ottawa Airport while 50 cm sits on the ground.

A 10× unit error on the headline number is what the criterion calls out ("a unit error fails"), so
the row is FAIL. The retrieval and arithmetic underneath it are sound and reproducible.

## Stability

| check | result |
|---|---|
| crash signatures (`SIGSEGV` / `device lost` / `ErrorDeviceLost`) | **0** |
| requests served | 531 · max single-request prompt **51,383** tokens |
| weighted draft acceptance | **77.96 %** (55,183 / 70,784) |
| compactions during A3 | 2 (tuned trigger) |
| `b70-sycl` RestartCount | 0 → **0** (untouched) |

## Restore

`xtx-vulkan` started, `/health` ok, worker `ready`, and a **routed request through SMG returned a
real completion** (`ok`) — no circuit-breaker stuck-open, so no router restart was needed this time.

> The fingerprint came back `b1-b1b770d`, i.e. **v1.0.0**, not the `b1-8642541` (v0.8.0) the
> container was running on 2026-11-12: `:latest` has moved on and the restart picked it up.
> Upstream `v1.0.0` = `b1b770d90` (2026-11-13), and **b12375 is after it**, so this dev build sits
> on top of the v1.0.0 tag.

## Verdict

**Do not promote b12375.** 5/8, with three distinct failures:

- **T2**: a structurally broken SVG (`</radowGrad>`) — the first T2 failure we have recorded on this
  model, and the only one that could plausibly be build-related rather than model-related. One
  sample is not enough to say; re-running T2 a few times would separate a regression from variance.
- **A3**: unit error (cm reported as mm). Not a backend property.
- **V3**: 113S vs 118S plus an invented brand — the same model-level anchoring error as every
  previous run on this image.

Nothing in the build's own delta is exercised by this battery. If promotion is being considered on
the strength of v1.0.0 plus this dev line, the useful next step is a decode/acceptance comparison
against the running v1.0.0 container (the v0.9.0 → b12182 measurement found +1.3 % on t2 and no
memory change), not another battery pass.
