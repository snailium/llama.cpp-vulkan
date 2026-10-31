# Vulkan Test Report — 7900 XTX · server-dev-m26.2-b12020-20261031-1054

**Date**: 2026-10-31 (run window 13:04–13:27 UTC)
**Host**: `home-ai` (192.168.111.101). The Session ran on the control host `PC-DEV` (.90); every GPU
action crossed `scripts/on-gpu.sh`. Reachability confirmed with `--check` (`host : home-ai`) before
anything else.
**Card tested**: AMD RX 7900 XTX (24 GB), `Vulkan0` = *AMD Radeon RX 7900 XTX (RADV NAVI31)*,
`0000:10:00.0`, ICD pinned with `VK_DRIVER_FILES=…/radeon_icd.json`
**Backend**: `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-dev-m26.2-b12020-20261031-1054`
**Model**: `/models/Qwen3.8-27B-Q4_K_M.gguf` (+ `mmproj-…-Q8_0.gguf` on GPU, `mtp-…-Q4_0.gguf` draft)
**KV precision**: **`q8_0` K / `q4_0` V**, draft KV `q8_0`/`q4_0` — this is **not** the SYCL golden's
q8_0/q8_0, so no Vulkan-vs-SYCL decode number here is a pure backend comparison.
**Speculative decoding**: `draft-mtp`, **K = 4** (`--spec-draft-n-max 4`), p_min 0.1. Acceptance is
only comparable at equal K.
**Image digest**: `sha256:b108718a43e01d0fb0ed694c77a4016c1929c7e775c7277f9232c29c56894a83`
**Harness digest**: `sha256:1780ca835360cf592779a07584fd1cf265ad29b7cb77cd844ae06442b10fdb11`
(`ghcr.io/snailium/dsh-container/dsh:latest`, dsh **0.2.1-rc.2**)
**Skill sha256**: `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53`
(prompts parsed from that file at run time, never transcribed)

**Sampling**: inherited from the backend as deployed — read back from `/props`, not from the launch
flags and **not** from the startup log: `temperature 0.7`, `top_p 0.80`, `top_k 20`, `min_p 0.0`,
`presence_penalty 1.5`, `frequency_penalty 0.0`, `repeat_penalty 1.0`, `n_ctx 131072`, 1 slot.
Only two request fields were sent: `chat_template_kwargs.enable_thinking=false` (task protocol) and
`max_tokens=32768` (generation cap). `stream=true` on T1/T2/V1–V3 is transport, needed for TTFT.

**Trim auto-tune**: **on** (`DSH_TRIM_AUTO_TUNE=1`). Effective compaction trigger **104 857 tokens =
80 %** of the 131 072 window, `headroomTokens=9831` (persisted row:
`(131072−16384) − floor(0.8×131072)`), target route `/models/Qwen3.8-27B-Q4_K_M.gguf` on provider
`lc`. Log line: `context-trim: auto compaction tune: Retuned compaction-basic …`.
Repeat-tool-breaker (`dsh-repeat-tool-breaker` 0.11.6) was tightened for A3 only:
`onLimit: deny, exact/cmd/net/sink: 5, host: 12` — the loop measures catch the measured loop shape
while leaving a legitimate multi-page single-host scrape possible.

**Capture mode**: server ran **without `-v`** (only `-lv 4` at launch, for the loader's device/buffer
detail). Consequence, stated because it bounds the numbers: per-request `timings` JSON is **absent**
from the server log, so:
- T1/T2/V1–V3 metrics come from the client-side `timings` block of each streamed response (full
  fidelity, one request per task);
- A1–A3 metrics come from `slot print_timing`, whose coverage is partial — the agent rows report
  **"requests that emitted timings"**, not the task's model-request count (A1 13 vs 12 requests,
  A2 5 vs 4, A3 151 vs 149). All rates are **weighted** (`Σtokens/Σms`), never averaged.

---

## What changed vs the outgoing baseline

| | candidate | baseline (`:latest` = the v0.8.0 dual-target run) |
|---|---|---|
| llama.cpp | `0.8.0-dev`, commit **`0ec4027`** (build 1) | `0.8.0-dev`, commit **`8642541`** |
| Mesa | **26.2.6**~kisak1~r | **26.2.5**~kisak1~r |
| libvulkan1 | 1.4.341.0-1 | 1.4.341.0-1 |
| digest | `sha256:b108718a…` | `sha256:842e09dd…` |

**⚠️ The Mesa bump is the bigger change on this backend.** Mesa `26.2.5 → 26.2.6` moves the entire
Vulkan/RADV code path the card executes on, while the llama.cpp move is one commit. Any decode or
acceptance delta below therefore cannot be attributed to llama.cpp alone. No regression appeared, so
26.2.6 is not a blocker — but a future bisect of a Vulkan perf change has to start with the driver.

---

## Results (7900 XTX)

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 147.6 (server pp) | 0.802 | 6 102 | 87.1 | 71.3 % (4517/6336) | balanced HTML, `<html>/<head>/<body>`, ends `</html>`, `finish_reason=stop` |
| T2 | **PASS** | 32 | 123.1 | 0.537 | 9 974 | 95.2 | 83.2 % (7668/9220) | well-formed XML, single `<svg>` root, `viewBox` present, ends `</svg>`, `stop` |
| A1 | **PASS** | 42 950 (13 req w/ timings) | 536.8 | 3.27 median, 23.13 max | 4 057 | 45.6 | 43.5 % (2569/5908) | 13 findings (H1–H3, M1–M4, L1–L6), each with risk, reason, fix and `file:line`; 3 spot-checked against source — all real (see below) |
| A2 | **PASS** | 8 853 (5) | 720.6 | 0.83 median, 8.76 max | 1 021 | 81.9 | 69.2 % (747/1080) | valid JSON; values **gathered** with 3 `bash` calls (`lscpu`, `free`, `df`, `os-release`, `uname`, cgroup); correct for the harness host |
| A3 | **FAIL** | 113 061 (151) | 416.9 | 0.73 median, 66.99 max | 18 491 | 74.9 | 79.5 % (13973/17572) | number **258.6**, source (ECCC GeoMet `climate-daily`, station 6106001), method and per-month breakdown correct — but **labelled `mm`; `TOTAL_SNOW` is `cm`** → unit error |
| V1 | **PASS** | 3 528 | 465.8 | 10.233 | 732 | 72.1 | 55.2 % (503/912) | 莉拉 / LV 700; popup 必杀技 千律 LV6, 达成XR2阶级时激活, 850 % + 400 %, 防御力减少75 %, 沉默 — all match ground truth, and the extra details it quoted (AWAKE/BLOSSOM tabs, `EP −1000`, `20M 45°`, `4M`) are genuinely on the screenshot (verified by inspection) |
| V2 | **FAIL** | 1 064 | 561.5 | 2.401 | 2 355 | 70.7 | 51.7 % (1587/3068) | ~12 true labels (DIMM1–4, PCIE16X, M2_1, M2_2, USB2_LAN, HDMI, VGA, AUDIO, CODEC, F_PANEL) but **invented** `SATA0–3`, `X2`, `U6`, `U66…U100`, `L1…Lxx`, `Cxxx`, `Rxxx`, `TPxx`, `CPU_FAN/CH_FAN/SYS_FAN`; `FCH`, `USB31A`, `USB32A`, `L23`, `L21` missing; `F_AUDIO` read as `FAUDIO` |
| V3 | **FAIL** | 4 160 | 263.7 | 16.385 | 675 | 60.4 | 41.9 % (422/1008) | size `255/70R18` correct, `M+S` + three-peak snowflake correct; load/speed read **`LT180`** where truth is **`118S`**; asserted **BFGoodrich All-Terrain T/A KO2** where the ground truth says the brand is unreadable — and echoed the prompt's decoy "All-Terran" wording |

Vision ran with the projector **on the GPU** (no `LLAMA_ARG_MMPROJ_OFFLOAD`), the golden's XTX
arrangement; image prefill 264–562 t/s is the GPU-encoder range, not the ~50–100 t/s CPU range.

### A1 review coverage (observation — reported, never gating)

```
files touched / inventory : 13 / 27  (48 %)
read calls               : 12
missed                   : .dockerignore, .github/workflows/{ci,release}.yml, .gitignore, LICENSE,
                           README.md, go.sum, bridge_test.go, fakeclient_test.go, infer_test.go,
                           store_test.go, uniqueid_test.go, web_handler_test.go, yamlstore_test.go
notable                  : all 7 _test.go files skipped — the same gap as every previous run
                           (44 %/44 %/56 % on 2026-09-27); a scope choice, not scored
```

**Grounding spot-check of A1 (fabricated findings fail this task).** Three claims read against the
clone the agent made itself: `websec.go` `requireWrite` really does accept `POST` **and** `PUT`
(line ~46); the `Dockerfile` really does `EXPOSE 8080` (line 29); `yamlstore.go` really does
sanitize `/\ # + *` to `_` (~line 103) and resolve back by scanning known devices (~line 112), i.e.
the collision it describes is real. All three hold.

---

## B70 — NOT TESTED (N/A, non-gating)

The issue's image is a **dev** candidate (`server-dev-*`), where **the 7900 XTX passing is sufficient
to promote** and a B70 failure neither blocks promotion nor is a blocker: the B70's production path is
SYCL. The B70 card was also **occupied by a different, in-flight SYCL run at the time**
(`b70-b12019-test` on :18082, its A1/A2/A3 sequence visible in `issue34-run/`, with `b70-sycl` stopped
for that run's card exclusivity), so a Vulkan B70 run would have had to interrupt work that was not
mine. Per the user's explicit instruction for this run, B70 was therefore **skipped as non-gating**
rather than taken over later in the window.

| Task | B70 |
|---|---|
| T1, T2, A1, A2, A3, V1, V2, V3 | **N/A — not run.** Dev channel: B70 non-gating; card under another run's exclusivity; skipped by explicit instruction. No B70 number in this report is measured, and none is inferred from the XTX. |

Consequence to keep in mind for a future promote: if this digest is ever proposed for `:stable`,
**both** cards must pass, and the B70 half of this evidence would have to be produced first.

---

## Stability

| Check | Result |
|---|---|
| Test container `RestartCount` / `OOMKilled` | **0 / false**; `ExitCode=0` on removal; state `running` at end |
| Crash signatures in the 8 988-line server log (`device lost`, `ErrorDeviceLost`, ring timeout, SIGSEGV, `stack smashing`, `GGML_ASSERT`, `terminate called`, alloc failure) | **0** |
| `E`-level / error lines in the server log | **0** |
| Kernel ring (`dmesg`, 3 426 lines readable) — any `amdgpu` / `drm` event | **0** |
| GPU devcoredump created | **none** (watchdog was armed before A3 because that task reaches the trim trigger at 104 857 tokens on a card with 726 MiB free; `/sys/class/devcoredump/disabled = 0`, nothing captured) |
| Truncation | none — every task returned `finish_reason=stop` |
| Other card's `RestartCount` (`b70-sycl`) before → after | **0 → 0** (it stayed up and `ready` in the router; the run did not leak outside its card) |
| Free VRAM after load | **726 MiB** of 24 560 (used 23 833) — matches the golden's 720 MiB; the loader's `failed to fit params to free device memory … need to reduce by 282 MiB` line is the known false alarm, not an OOM |
| Verification of offload | `load_tensors: offloaded 65/65 layers to GPU`, main `Vulkan0 model buffer size = 17402.38 MiB`, draft 66/66 = `774.71 MiB`, `flash_attn = enabled`, `n_ctx = 131072`, `spec … n_max=4, cache_k=q8_0, cache_v=q4_0` |

The KV config was verified through the **correct** env name (`…_CACHE_TYPE_K/_V`): the loader printed
`cache_k=q8_0, cache_v=q4_0`, not the f16 default that the misspelled `…_TYPE_K` would have produced.

---

## Restore of production (verified in order, not just `/health`)

`xtx-vulkan` (:18090) was stopped for the exclusive run (user consent obtained first; `b70-sycl` was
left serving). Restore sequence afterwards:

1. `docker start xtx-vulkan` → `/health` `{"status":"ok"}` after 3 s
2. direct inference on :18090 → `ok`, `finish_reason=stop`
3. **routed** inference through SMG :40114 with `X-SMG-Routing-Key` → HTTP **200**, `ok` (0.29 s / 0.44 s)
4. `/workers` → `18090 healthy=True status=ready`, `18080 healthy=True status=ready`

Step 3/4 needed patience: immediately after the restart SMG still reported 18090 as
`healthy=False status=failed` (its health probe had been failing with `Connection refused` while the
card was down), and its own log shows the recovery at **13:27:32**
`Worker status transition … old=Failed new=Ready`. No `docker restart smg` was needed; the router
closed the circuit itself ~4 minutes after the worker came back. Recorded because a 200 from a
two-worker router does **not** by itself prove the restarted worker is in rotation — `/workers` is the
check that does.

Production state after the run: `xtx-vulkan` running, `RestartCount=0`, `OOMKilled=false`; `b70-sycl`
running, `RestartCount=0`.

---

## Verdict

**7900 XTX: no backend regression — the card passes the promote gate for the dev channel.**

- Backend-fault count: **zero** (no crash, no device loss, no OOM, no ring reset, no truncation, no
  config silently dropped). This is the axis the gate exists for, and it is clean.
- Throughput is in line with the outgoing `v0.8.0` baseline within run-to-run noise: T1 87.1 vs 91.0,
  T2 95.2 vs 97.1, A3 74.9 vs 75.3, V2 70.7 vs 66.7, V3 60.4 vs 61.2, V1 72.1 vs 69.8 t/s. A1 45.6 vs
  41.5 and A2 81.9 vs 91.1 are single-run figures on different content — read as noise, not a signal.
- The three FAILs are **model-quality, not backend**, and all three reproduce on the outgoing image:
  A3 labels `TOTAL_SNOW` as mm (ECCC reports **cm**), V2 invents motherboard designators, V3 misreads
  the tyre load/speed index and asserts an unreadable brand. The identical failures were recorded for
  `v0.7.0` and `v0.8.0` on both cards, so they are not a property of this digest.

**No promotion was performed.** This is a `server-dev-*` candidate, and `promote-vulkan-image.sh`
tags `:stable` + a semver — the **stable** channel, whose gate requires **both** cards. With the B70
half deliberately not run, promoting this digest to `:stable` would publish a stable anchor that one
of the two supported cards has never been validated on. The dev-channel step (moving the
`:server-dev` pointer at digest `sha256:b108718a43e01d0fb0ed694c77a4016c1929c7e775c7277f9232c29c56894a83`)
is the one this evidence supports, and it was left to the operator rather than done unilaterally.

What would change the verdict: a stable-channel request (**then** the B70 half must be produced first);
a repeat of any run showing a crash, a device-lost, or a free-VRAM collapse on this card; or a future
bisect that attributes a decode drop to Mesa 26.2.6 rather than to llama.cpp.

---

## Files

- `results/t1_html_result.json`, `results/t2_svg_result.json`, `results/v{1,2,3}_result.json` — full
  responses with the client-side `timings` block (the authoritative compute metrics for direct tasks)
- `results/*_raw.jsonl` — raw SSE for every direct task
- `results/docs/t1_html.html`, `results/docs/t2_svg.svg` — outputs with the code fence stripped
- `evidence/server.log` — the backend's full log with RFC 3339 timestamps (metric source for A1–A3)
- `evidence/windows.json` — the per-task wall-clock windows used to split that log
- `evidence/climate-daily-schema.json`, `evidence/yow-dec2025.json` — the data used to settle A3's
  unit question (see below)
- `sessions/*.jsonl` and `sessions/*.jsonl.zstd` — all four dsh sessions, decompressed and byte-exact
- `launch-xtx.sh` — the exact container launch (golden config, env-var form, no sampling flags)

### How A3's unit was settled (not asserted)

The monthly total for December 2025 from the agent's own source is 54.6. ECCC also reports
`TOTAL_PRECIPITATION` in **mm** for the same days, so a per-day water balance decides the unit:
2025-12-07 has `TOTAL_SNOW = 3.6` with `TOTAL_PRECIPITATION = 2.7 mm` at a mean −12.1 °C. If 3.6 were
**mm** of snow, its water equivalent (≈0.36 mm) would be 13 % of the day's precipitation at a
temperature where all precipitation is snow — impossible. Read as **cm**, 3.6 cm ≈ 3.6 mm of water
against 2.7 mm of precipitation is a normal dry-snow ratio. Monthly, "mm" would make December's snow
120 % of its precipitation. So `TOTAL_SNOW` is cm and the answer's unit is wrong while its number,
source and method are right.
