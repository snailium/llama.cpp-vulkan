# Long-context agentic decode — per-depth scan (B70 Vulkan vs SYCL, RDNA3 control)

**Date:** 2026-09-10 · **Card:** Intel Arc Pro B70 (32 GB, BMG-G31 / Xe2) · **Model:** Qwen3.8-27B-Q4_K_M (+ MTP3 Q8_0 draft)

This is the report we are promoting: a **per-depth decode-throughput scan** on a single
prosumer/workstation GPU running llama.cpp, isolating **backend-intrinsic deep-context
collapse** from model and KV-quant effects. It is the "honest single-session baseline" that
datacenter serving benchmarks (MLPerf Agentic Inference, SemiAnalysis AgentX) cannot show,
because their batching engines mask the per-session KV-growth cost.

## Why this test

Standard llama.cpp microbenchmarks (`pp512`/`tg128`) measure **short-context** decode and
miss the regime that actually hurts real agent sessions: a coding/agent loop whose context
grows to 50–75k tokens over many turns. The new [MLPerf Agentic Inference](https://mlcommons.org/2026/07/agentic-inference-for-mlperf-inference/)
and [SemiAnalysis AgentX](https://inferencex.semianalysis.com/blog/agentic-benchmark-agent-benchmark-guide)
benchmarks cover agentic *serving* (concurrency, cache reuse, cost on datacenter GPUs with
vLLM/SGLang/TRT-LLM), but none of them measure **per-token decode rate as one session's KV
grows on a single consumer/prosumer card** — the exact thing that determines whether your
agent feels fast or crawl at depth.

We close that gap with a controlled per-depth scan. (Filed upstream as [ggml-org/llama.cpp#28721](https://github.com/ggml-org/llama.cpp/issues/28721).)

## Method

One chat request per depth; the user message is the KV filler (prefill), then a **96-token
decode**; `timings` read from the streamed response. Same model, MTP3 draft, sampling, and
KV type across backends. Runner: [`depth_scan.py`](../depth_scan.py).

- `b70-vulkan-dev` = llama.cpp b10883 + Vulkan / Mesa 26.2.2 (kisak ANV)
- `b70-dev-test-v040` = SYCL v0.4.0 / c26.31
- KV q8_0 for both, plus a Vulkan f16-KV control

## Results — decode t/s by context depth

| depth (tokens) | Vulkan q8_0 KV | Vulkan f16 KV | SYCL q8_0 KV | Vulkan TTFT | SYCL TTFT |
|---|---|---|---|---|---|
| ~1k   | 35.6 | 33.4 | 38.5 | 1.8 s   | 1.8 s   |
| ~15k  | 14.9 | 13.3 | 31.7 | 43.2 s  | 23.2 s  |
| ~32k  | 8.4  | 8.2  | 22.8 | 94.1 s  | 28.5 s  |
| ~64k  | 4.5  | 4.3  | 15.8 | 329.0 s | 64.9 s  |

Raw: `depthscan-{vulkan-q8kv,vulkan-f16kv,sycl-q8kv}.json`.

## Findings

1. **Short-context decode is fine** — Vulkan 35.6 vs SYCL 38.5 t/s (−8%), both at the
   608 GB/s bandwidth ceiling (~37 t/s for a dense 27B). The "Vulkan is slow" perception
   comes entirely from deep context, not short-context decode.

2. **The collapse is backend-intrinsic on Vulkan.** Decode drops ~8x (1k→64k) on Vulkan vs
   ~2.4x on SYCL. f16 KV collapses identically → **not a KV-quant effect**. Draft acceptance
   is comparable (0.47–0.68) and lower on SYCL at depth, yet SYCL still wins → not an MTP
   artifact.

3. **MTP gain vanishes with depth on Vulkan only** (no-draft control): +66%→+9%→−14%
   (1k→16k→32k) on Vulkan, vs +71%→+69%→+43% on SYCL. See the MTP addendum in
   [`docs/VULKAN-PERF-RESEARCH-20260910.md`](../../docs/VULKAN-PERF-RESEARCH-20260910.md).

4. **Likely root cause:** `ggml-vulkan` forces the **scalar** flash-attention path at
   `n_rows == 1` (`get_fa_tuning_params`), so decode never uses matrix-core attention, and
   the scalar/large-KV FA degrades ~linearly with context. Kernel-maturity gap, not a driver
   or quant issue; recent matmul commits don't touch this path.

## RDNA3 control (7900 XTX does not collapse)

Third-party single run on **RX 7900 XTX** (Navi31/gfx1100), near-identical setup (Qwen-27B
GGUF + MTP, 32k ctx, 28k prompt + 2000-tok output, q8_0 KV, FA on): **Vulkan decode holds
~58–60 t/s at 28–30k depth** — no collapse, faster than our B70 short-context peak.
Source: [hcgdw/rx-7900-xtx-llm-benchmark](https://github.com/hcgdw/rx-7900-xtx-llm-benchmark)
(single run, directional). We will run the same per-depth scan on our 7900 XTX when it
arrives and add the curve here.

## Practical guidance (B70 / RDNA users)

- **Short-context dense work:** Vulkan ≈ SYCL; keep MTP3 on (pure +66–71% win).
- **Deep-context agent loops on B70/Vulkan:** expect the collapse; MTP3 is neutral-to-harmful
  at depth until upstream lands Xe2 FA/GEMM. Prefer MoE models for raw throughput, or SYCL
  if you must stay dense.
- **7900 XTX / RDNA3:** no evidence of the collapse; Vulkan is a first-class path. Verify
  Mesa/RADV ≥ 25.3 and ReBAR enabled (see `METHODOLOGY.md`).

## Reproduce

```bash
# per-depth decode scan against any OpenAI-compatible llama-server
export DEPTH_SCAN_URL=http://192.168.111.102:18082/v1
export MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
export KV_LABEL=vulkan-q8kv            # label for the output file
export DEPTHS=1024,15360,32768,65536
python3 benchmark/depth_scan.py        # writes benchmark/results/depthscan-<KV_LABEL>.json
```
