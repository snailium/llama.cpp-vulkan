# Benchmark results

One file per dated test run: `YYYY-MM-DD-<card>-<config-slug>.md`. Format and rules in [`../METHODOLOGY.md`](../METHODOLOGY.md).

## Reports

| Date | Report | Card | Notes |
|---|---|---|---|
| 2026-09-10 | [Long-context agentic decode — per-depth scan](2026-09-10-long-context-agentic-depth-scan.md) | B70 (Vulkan vs SYCL) + RDNA3 control | Headline: Vulkan deep-context decode collapses ~8x; RDNA3 does not. Raw JSON below. |
| 2026-09-10 | [Vulkan v0.4.0](2026-09-10-vulkan-v040.md) · [Vulkan dev b10883](2026-09-10-vulkan-dev-b10883.md) | B70 | T1–T5 suite + session perf. |
| 2026-09-23 | [XTX context ceiling](2026-09-23-xtx-context-ceiling.md) | 7900 XTX (Vulkan) | Headline: real ceiling is ~287 K, not the configured 128 K; cliff at 292864→293888 collapses decode 6.5x while free VRAM *increases*. |
| 2026-09-23 | [B70 deep-context collapse fixed in b11117](2026-09-23-b70-deep-context-collapse-fixed.md) | B70 (Vulkan) | Headline: 64 K depth decode 4.5→24.0 t/s vs b11064. |
| 2026-10-25 | [XTX T1/T2 perf: b11850](2026-10-25-xtx-t12-b11850.md) | 7900 XTX (Vulkan) | T1/T2 only, 3 reps. Decode looks −3.6 % on t1 but is **fully explained by a −3.92 pp acceptance fluctuation** (decode = 1.102 × accept + 12.65, residuals <1 t/s, no image effect). TTFT flat. **No difference; do not promote.** |
| 2026-10-25 | [XTX smoke: b11850](2026-10-25-xtx-smoke-b11850.md) | 7900 XTX (Vulkan) | Issue #14 candidate. Only our-model change is the qwen35 output reshape; **greedy output byte-identical on 3 prompts**, decode/draft identical. No reason to promote. |
| 2026-10-24 | [XTX checkpoint mechanism](2026-10-24-xtx-checkpoint-mechanism.md) | 7900 XTX (Vulkan) | **Why the cost is constant**: `PARTIAL_ONLY` + `swa_type == NONE` skips the KV write entirely; only the **1-cell** recurrent snapshot (149.62 MiB) is stored. Plateau = 32 × 149.626 = 4.68 GiB. Rule: non-SWA hybrid → constant, SWA → depth-proportional. |
| 2026-10-24 | [XTX 130k depth — no OOM](2026-10-24-xtx-130k-depth-no-oom.md) | 7900 XTX (Vulkan) | **Falsifies the `ctxcp x depth` worst case.** Driven to 130,588 tokens: peak RSS 6,465 MiB, checkpoints cost **4.5 GiB not 108 GiB**, live set saturates after ~32k depth. **Keep the default 32**, do not set 4. |
| 2026-10-23 | [XTX context checkpoints — verified](2026-10-23-xtx-context-checkpoints-verify.md) | 7900 XTX (Vulkan) | Confirms checkpoints cost host RAM (VRAM flat): **+3.4 GiB at depth 20.8k**, **27,734 B/token**. Default 32 needs **108 GiB at 128k** → OOM. **Set `--ctx-checkpoints 4`.** |
| 2026-10-23 | [B70 Vulkan: v0.7.0 vs dev b11706](2026-10-23-b70-vulkan-v070-vs-b11706.md) | Arc Pro B70 (Vulkan) | Single B70-relevant change in b11706 is `intel_shader_core_count` 0→32. **Prefill −0.45 % to −1.85 %, i.e. no gain.** Also documents that the Vulkan image does **not** pin `LLAMA_ARG_PORT`, so ad-hoc runs listen on **9931**. Not worth adopting. |
| 2026-10-16 | [Muse-Glimmer SIGSEGV — root cause](2026-10-16-muse-glimmer-sigsegv-root-cause.md) | 7900 XTX (Vulkan) | **Root cause: thread-stack exhaustion in chat-template rendering.** SIGSEGV at ~30-40 KB of rendered content, 8 MiB default stack; gdb shows the stack gone inside `operator new`. `--ulimit stack=67108864` **fixes it** (wall moves ~20k → ~50k tokens). Qwen on the same image is unaffected. |
| 2026-10-16 | [Muse-Glimmer · context pressure scan](2026-10-16-muse-glimmer-xtx-context-pressure.md) | 7900 XTX (Vulkan) | **SIGSEGV at ~21.6k prompt tokens**, reproduced on 17gb/dynamic/no-drafter, with up to **5641 MiB free**. Usable ctx ~16% of declared. See [plot](2026-10-16-pressure-scan.png). |
| 2026-10-16 | [Muse-Glimmer-30B · dynamic · everything on GPU](2026-10-16-muse-glimmer-30b-xtx-dynamic-full.md) | 7900 XTX (Vulkan) | Headline: **6/8 PASS** at 481 MiB free; A3 gives a *third* distinct wrong answer, V1 truncated, V2 best-yet 17/21. Also documents a **grader bug** that produced a false T2 FAIL. |
| 2026-10-16 | [Muse-Glimmer-30B · v0.7.0 · f16 KV · DFlash](2026-10-16-muse-glimmer-30b-xtx-v070-f16kv-dflash.md) | 7900 XTX (Vulkan) | Headline: drafter confirmed active, decode **56.9-95.1 t/s** vs ~42 without. **6/8 PASS** — A3 and V3 regressed vs report #1 and failed *differently*. 3172 MiB free. |
| 2026-10-13 | [Muse-Glimmer-30B on the XTX — first run](2026-10-13-muse-glimmer-30b-xtx-first-run.md) | 7900 XTX (Vulkan) | Headline: **8/8 PASS on first attempt**, decode 40-42 t/s flat, 6434 MiB free at 131072 ctx. Official Meta GGUF. Beats Qwen on A2 (GPU naming) and V3 (tyre trap). No drafter; n=1. |
| 2026-10-04 | [XTX b11368 — XTX only](2026-10-04-xtx-b11368-xtx-only.md) | 7900 XTX (Vulkan) | Headline: no regression vs the promoted b11165; T1/T2 + A1/A3 pass, A2 GPU naming and V2/V3 reproduce known model behaviour. **This image lacks our local patch** (built from `main` before `3b4a2365f`). ⚠️ Contains a **Corrections** section: T1/T2/A1-A3 ran at non-golden sampling on a stale harness; V1-V3 were re-run correctly with mmproj on GPU. |

Raw per-depth scan JSON: `depthscan-{vulkan-q8kv,vulkan-f16kv,sycl-q8kv,vulkan-nodraft,sycl-nodraft}.json` (runner [`../depth_scan.py`](../depth_scan.py)).

> The 7900 XTX context-ceiling scan is in (2026-09-23); a per-depth scan on RDNA3 is still pending.
