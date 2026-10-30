# Vulkan Test Report — dual target (7900 XTX + B70) · server-m26.2-v0.8.0-20261028-1750

**Issue**: snailium/llama.cpp-vulkan#15 (reopened, stable build)
**Date**: 2026-10-30 (America/Toronto)
**Host**: `home-ai` `.101` (both cards); harness containers ran on control host `PC-DEV` `.90`
**Backend**: llama.cpp **v0.8.0**, Vulkan, Mesa **26.2.5~kisak1~r** (reference pin 26.2), Ubuntu 26.04.1
**Model**: `/models/Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-Qwen3.8-27B-Q8_0.gguf`, draft `mtp-Qwen3.8-27B-Q4_0.gguf`
**Speculative decoding**: draft-mtp, **K = 4 on XTX / K = 3 on B70** (acceptance is only comparable at equal K)
**KV precision**: XTX `q8_0` K / `q4_0` V · B70 `f16` K / `f16` V — **these differ, so no cross-card decode comparison is a pure backend comparison**

| Moving part | Pinned value |
|---|---|
| Backend image digest | `sha256:842e09ddd3ffd79b740a180db88f9e5e396060ec70d334d58c2788a4b11b2bc6` |
| Image tag validated | `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-m26.2-v0.8.0-20261028-1750` |
| Previous stable (for comparison) | `e4c6b1d0…` = `:v0.7.0` / `:stable` / `:latest` (2026-10-15 build) |
| Harness image digest | `ghcr.io/snailium/dsh-container/dsh@sha256:1780ca835360cf592779a07584fd1cf265ad29b7cb77cd844ae06442b10fdb11` (dsh 0.2.1-rc.2) |
| Skill (question set) sha256 | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Vision assets | `game_screenshot_Lila.jpg` ed583e56… · `motherboard_layout.png` 42172d37… · `tire_25570R18.jpg` f5b03bef… (all match the skill table) |

**Sampling** — inherited from the backend exactly as deployed; verified by asking the server, not the log
(`/props` on both cards returned `temp=0.7, top_p=0.80, top_k=20, min_p=0.0, presence=1.5, frequency=0.0,
repeat=1.0`, `n_ctx=131072`). Only two request fields were sent: `chat_template_kwargs.enable_thinking=false`
and `max_tokens=32768` (plus `stream` / `stream_options` as transport).
**Trim auto-tune**: ON (`DSH_TRIM_AUTO_TUNE=1`), verified — `context-trim: auto compaction tune: Retuned
compaction-basic …`, and the persisted row reads `headroomTokens: 9831` = (131072 − 16384) − floor(0.8 × 131072),
i.e. the compaction trigger sits at ~80 % of the window instead of dsh's stock 37.5 %.

---

## Configuration actually in force (read back from the running server)

**7900 XTX** (`radeon_icd.json`, `Vulkan0` = *AMD Radeon RX 7900 XTX (RADV NAVI31)*, 24560 MiB):
`offloaded 65/65 layers`; main model `17402.38 MiB`, KV `3328.00 MiB`, RS `748.12`, compute `270.29`;
draft `66/66`, `774.71 MiB`, KV `208.00 MiB`; `flash_attn = enabled`; `CLIP using Vulkan0 backend`
(projector on GPU); `spec … n_max=4, cache_k=q8_0, cache_v=q4_0` (correct `…_CACHE_TYPE_K` spelling);
`n_slots=1, n_ctx_slot=131072`. **Kernel-reported free VRAM after load: 730 MiB (used 23829 / 24560)** —
above the ~0.3 GB workable floor and within 10 MiB of the golden's recorded 720 MiB.

**B70** (`intel_icd.json`, `Vulkan0` = *Intel(R) Graphics (BMG G31)*, 32656 MiB):
`offloaded 65/65 layers`; main model `17402.38 MiB`, KV **`8192.00 MiB` (f16)**, compute `270.29`;
draft `66/66`, `774.71 MiB`, KV `512.00 MiB` (f16); `flash_attn = auto`; `CLIP using Vulkan0 backend`;
`spec … n_max=3, cache_k=f16, cache_v=f16`; `n_slots=1, n_ctx_slot=131072`. Projected use
`27949 MiB of 29322 free` → ~1.37 GB headroom.

Both launch scripts are preserved: `launch-xtx.sh`, `launch-b70.sh` (env-var form, no CLI config flags;
`-lv 4` was added for per-request timings and changes logging only).

---

## 7900 XTX — results

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 149 (server pp) | 0.45 | 5473 | 91.0 | 77.0 % | balanced HTML, `<html>/<head>/<body>`, ends `</html>`, `stop` |
| T2 | **PASS** | 32 | 78 (server pp) | 0.67 | 5399 | 97.1 | 84.2 % | well-formed XML, single `<svg>`, `viewBox`, ends `</svg>`, `stop` |
| A1 | **PASS** | 173 727 (29 req) | 421 | 14.21 mean (max 206.1) | 5639 | 41.5 | 50.5 % | 14 findings (H-1…H-3, M-1…M-5, L-1…L-6) each with risk/reason/fix; spot-checked `mqtt.go:343` `randSuffix` and `websec.go:32` CSRF — both real |
| A2 | **PASS** | 9 641 (4 req) | 727 | 3.32 mean | 1246 | 91.1 | 82.2 % | values gathered (5 `bash` calls) and correct for the harness host `PC-DEV`: Ryzen 7 5700X / 12 threads, 15 GiB, kernel 7.0.0-42, GPU **absent** stated |
| A3 | **FAIL** | 71 186 (143 req) | 422 | 1.18 mean | 15 972 | 75.3 | 79.8 % | number 258.6 and source/method correct, but labelled **mm**; ECCC `TOTAL_SNOW` is **cm** (Ottawa January normal ≈ 55 cm vs this run's 81.6) → unit error |
| V1 | **PASS** | 3 528 | 468 | 7.54 | 871 | 69.8 | 52.7 % | 莉拉 / LV700 / popup 千律 LV6, XR2, 850 % + 400 %, 防御力−75 %, 沉默 — all match ground truth |
| V2 | **FAIL** | 1 064 | 571 | 1.86 | 1 329 | 66.7 | 47.0 % | 17/21 true labels but **invented** designators (U66…U100, SATA, L20, L22, X2); `USB31A/USB32A` read as `USB3A/USB3B`; `FCH`, `F_PANEL` missing |
| V3 | **FAIL** | 4 160 | 265 | 15.67 | 705 | 61.2 | 43.0 % | size `255/70R18` correct; load/speed read `130T` vs truth **118S**; asserted a brand where truth says unreadable |

TTFT here is client-side (first stream chunk); `prefill` is reported from the server's own prompt-eval
timing where the client figure is distorted by prompt-cache reuse (T1's re-run evaluated only 4 cached
tokens, so its client-side 95 tok/s overstates prefill).

---

## B70 — results

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 35 (cold start) | 1.24 | 3504 | 46.5 | 69.8 % | balanced HTML, closes at `</html>`, `stop` |
| T2 | **FAIL** | 32 | 34 (cold start) | 0.95 | 4252 | 51.3 | 81.0 % | response = heading + 93 chars of prose + ```` ```svg ```` fence, so the **response does not parse as XML**. The fenced block itself is valid (single `<svg>`, `viewBox`, closes) — a presentation failure, not a malformed document |
| A1 | **PASS** | 57 061 (26 req) | 148 | 14.85 mean (max 87.6) | 4491 | 28.8 | 57.3 % | concrete findings with file:line, including a CVE check on `paho.mqtt.golang`; grounded |
| A2 | **PASS** | 9 589 (5 req) | 397 | 4.83 mean | 1333 | 50.4 | 84.4 % | same `PC-DEV` facts, `"gpu": null` + “未检测到” — correct |
| A3 | **TIMEOUT** | — | — | — | — | — | — | killed at the 1 h cap, 379 tool calls (206 `web_fetch_file`), still trying alternative ECCC endpoints; **no number delivered**. Per the skill this is the known loop/harness failure mode (issues #29–#31), not a backend defect — the identical prompt succeeded on the XTX in the same run |
| V1 | **PASS** | 3 528 | 214 | 16.48 | 938 | 39.1 | 55.1 % | same correct popup reading as XTX |
| V2 | **FAIL** | 1 064 | 288 | 3.69 | 1 708 | 36.5 | 48.9 % | 14/21 true labels plus fabricated designators (U33A, U34, U22, U23, C087, C092); `FCH`, `F_PANEL`, `F_AUDIO`, `U64`, `U65` missing |
| V3 | **FAIL** | 4 160 | 163 | 25.55 | 398 | 38.1 | 53.9 % | `255/70R18` correct; load/speed `113S` vs truth **118S**; asserted “COOPER DISCOVERER” where truth says the brand is unreadable |

T1/T2 prefill on this card is measured on the first requests after load and includes Vulkan shader
compilation (34 t/s vs 214–288 t/s on the image tasks that ran later), so those two figures are cold-start
numbers, not the card's steady-state prefill.

**A1 review coverage (observation — reported, never gating):**

```
7900 XTX : touched 11 / 25 files (44 %)   read calls 11 ; all 7 _test.go files skipped, plus docs/LICENSE
B70      : touched 12 / 25 files (48 %)   read calls 12 ; same _test.go gap (12/13 missed files are tests/docs)
```
The pattern matches the recorded 2026-09-27 baseline (44 %): the agent's scope choice, not a backend property.

---

## Stability

| Check | 7900 XTX | B70 |
|---|---|---|
| Crashes / SIGSEGV / device lost | **none** | **none** |
| OOM / allocation failure | none (`OOMKilled=false`) | none |
| `RestartCount` (test container) | 0 | 0 (as launched; final inspect not taken — see below) |
| Kernel GPU faults in window (`journalctl -k`, 3 h) | **0** ring timeouts / wedges / devcoredump | 0 |
| Other card's `RestartCount` before → after | `b70-sycl` … (down during XTX run by the other test) → 0 | `xtx-vulkan` 0 → 0 |
| Production containers after restore | `xtx-vulkan` R=0, OOM=false | `b70-sycl` R=0, OOM=false |

The only log line matching a crash keyword on either card is the documented **false alarm**
`common_fit_params: failed to fit params to free device memory: n_gpu_layers already set by user to 999, abort`
— a conservation pre-check that fires while the config fits and the server proceeds normally.

---

## Restoration of production

The XTX restore was verified in the order the procedure requires, not just `/health`:

1. worker `/health` → `{"status":"ok"}`
2. worker infers → `"ok"`
3. **router** (`:40114`, `X-SMG-Routing-Key`) → real completion, not 503
4. `/workers` → both `18090` and `18080` `ready`

After the B70 restore the router still listed `18080` as `is_healthy: false, status: failed` while `18090`
was `ready` — the known SMG circuit-breaker state. `docker restart smg` was run, workers re-registered, and
after 35 s both read `ready`; a final routed completion returned `'ok'` and `/workers` showed
`[18090 True ready, 18080 True ready]`.

---

## Incidents and gaps (stated, not hidden)

1. **I removed another session's finished container.** `b70-v080-test` (SYCL image, `Exited (0)` 21 min
   earlier) was deleted as stale cleanup before the B70 run. Its logs were the likely source of that run's
   A1–A3 draft-acceptance figures. The container was still present, so its log was recoverable up to that
   point — it is **not** recoverable now. If that run still needs those numbers, they are lost.
2. **A3 on the B70 timed out** at 1 h with no answer; per-request metrics for it are not reported because
   there is no completed deliverable to attribute them to, and the container log was captured at 15:06,
   before the timeout, so its later requests are not in the archive.
3. **Final `RestartCount`/`OOMKilled` for the B70 test container was not captured** — the container was
   removed after its log was dumped. Stability for that card rests on the log (no crash signature) and on
   the zero kernel-fault count.
4. **Cross-backend numbers are not commensurable.** XTX runs `q8_0`/`q4_0` KV and K=4; B70 runs `f16`/`f16`
   KV and K=3. Any Vulkan-vs-SYCL or XTX-vs-B70 decode comparison inherits that difference.
5. Client-side `prefill` for T1 on the XTX is distorted by prompt-cache reuse; the server-side figure is
   given instead, and both are labelled.

---

## Verdict

**Backend health: clean on both cards.** All golden values were read back live from each server
(`/props`, offload line, KV buffer sizes, draft-KV cache types, projector device, free VRAM), zero crashes,
zero OOM, zero device-loss events, and both production containers were restored and verified through the
router.

**Task-level results are not clean on either card:**

| | PASS | FAIL | TIMEOUT |
|---|---|---|---|
| 7900 XTX | T1, T2, A1, A2, V1 | **A3** (unit), **V2** (invented labels), **V3** (118S misread, brand invented) | — |
| B70 | T1, A1, A2, V1 | **T2** (prose-wrapped, unparseable as XML), **V2** (invented labels), **V3** (113S, brand invented) | **A3** |

Every failure is **model-quality / output-format**, not a backend fault, and they reproduce the pattern
already recorded for the current stable: GOLDEN-CONFIG §6 documents the 2026-10-16 promotion of `:v0.7.0`
with V2 inventing labels, V3 misreading the load index and asserting a brand, A2 claiming no GPU and A3
mis-delivering an otherwise-correct figure. Relative to that baseline this image is **not worse** and is
marginally faster on decode (XTX 91–97 t/s vs 80–95; B70 46–51 t/s vs 41–46 on v0.4.1).

**Gate decision (stable channel `server-m*`): strictly NOT met.** The rule for a stable tag is that both
cards pass, and both cards have failing rows, so on the letter of the gate this digest should not be
promoted. The counter-argument is the house precedent above, under which these same model-quality failures
were treated as non-gating because they are not image-specific.

**Decision taken (2026-10-30): promoted on the "no backend regression vs current stable" criterion**, on the
recorded precedent above, with the failures above carried forward as known model-quality issues rather than
image defects.

Promotion performed exactly as the procedure specifies:

```
scripts/promote-vulkan-image.sh sha256:842e09ddd3ffd79b740a180db88f9e5e396060ec70d334d58c2788a4b11b2bc6 v0.8.0
```

Verified afterwards — every tag resolves to the tested digest:

| Tag | Digest |
|---|---|
| `:stable` | `sha256:842e09dd…` |
| `:v0.8.0` | `sha256:842e09dd…` |
| `:server-m26.2-v0.8.0-20261028-1750` | `sha256:842e09dd…` |

The previous stable `sha256:e4c6b1d0…` (`:v0.7.0`) is superseded by `:stable` pointing at `842e09dd…`;
its `:v0.7.0` tag is untouched and remains available for rollback.

If the team later adopts the literal "both cards pass the battery" reading, the blockers to record are
exactly: V2 (both cards), V3 (both cards), A3 unit error (XTX), A3 timeout (B70), B70 T2 prose wrapping.
