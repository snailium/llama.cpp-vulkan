<!--
FILED 2026-09-10 as ggml-org/llama.cpp#28721 (label: performance; no 'vulkan' label exists upstream).
  https://github.com/ggml-org/llama.cpp/issues/28721
Body below is the filed text. Keep in sync if you update the issue.
This is a measurement report + hypothesis, not a bug in the strict sense — we are happy
to help reproduce. All numbers below were measured by us on real hardware with the
reproduction recipe at the bottom.
-->

---

## Summary

On **Intel Arc Pro B70 (BMG-G31 / Xe2)** with the Vulkan backend, single-session
**decode throughput collapses ~8x as context grows from 1k to 64k tokens**, while the
same model on the SYCL backend degrades only ~2.4x over the same range. The collapse is
**backend-intrinsic**: it reproduces identically with f16 KV (not a KV-quant effect), and
it is **not present on AMD RDNA3 (RX 7900 XTX)**, where Vulkan decode holds up at depth.

This matters for real agentic workloads: a coding/agent session that grows to 50–75k
context sees 5–9 t/s on Vulkan vs 16–18 t/s on SYCL — the difference is entirely in this
deep-context regime, not in short-context decode (where the two backends are within ~8%).

## Reproduction (measured)

- **Model:** `Qwen3.8-27B-Q4_K_M` (dense, 16.4 GB weights), MTP3 draft (`Q8_0`, n-max 3, p-min 0.10)
- **GPU:** Intel Arc Pro B70 (32 GB, BMG-G31), single GPU, full offload
- **Backends:** `b70-vulkan-dev` = llama.cpp b10883 + Vulkan / Mesa 26.2.2 (kisak ANV);
  `b70-dev-test-v040` = SYCL v0.4.0 / c26.31
- **KV:** q8_0 for both; plus a Vulkan f16-KV control
- **Method:** one chat request per depth; the user message is the KV filler (prefill), then
  a 96-token decode; `timings` read from the streamed response. Runner: `depth_scan.py`.

| depth (tokens) | Vulkan q8_0 KV dec | Vulkan f16 KV dec | SYCL q8_0 KV dec | Vulkan TTFT | SYCL TTFT |
|---|---|---|---|---|---|
| ~1k   | 35.6 t/s | 33.4 t/s | 38.5 t/s | 1.8 s  | 1.8 s  |
| ~15k  | 14.9 t/s | 13.3 t/s | 31.7 t/s | 43.2 s | 23.2 s |
| ~32k  | 8.4 t/s  | 8.2 t/s  | 22.8 t/s | 94.1 s | 28.5 s |
| ~64k  | 4.5 t/s  | 4.3 t/s  | 15.8 t/s | 329.0 s| 64.9 s |

**Prefill also degrades on Vulkan only:** effective prefill falls 562 → 101 t/s (1k→64k),
giving a 329 s TTFT for a 33k-token prompt, while SYCL holds ~510–635 t/s across the range.

## Key observations

1. **Short-context decode is NOT the problem.** 35.6 (Vulkan) vs 38.5 (SYCL) t/s at 1k
   (−8%). Both are at the memory-bandwidth ceiling: a dense 27B reads ~16.4 GB of weights
   per token; B70's 608 GB/s GDDR6 ⇒ ~37 t/s theoretical. There is no headroom here, which
   is why recent matmul commits (#25773 spec-constant A-type, #27471 f16 B-type / Intel
   warp-tile tuning) changed nothing measurable for short-context decode on this card.

2. **KV quantization is not the cause.** Vulkan with f16 KV collapses identically
   (33.4 → 4.3 t/s, same shape as q8_0). Draft acceptance is also not the cause: acc is
   0.47–0.68 on both backends, and SYCL's acceptance is *lower* at depth yet still decodes
   much faster.

3. **MTP gain vanishes with depth on Vulkan only** (no-draft control, same scan):

   | depth | Vulkan no-MTP | Vulkan MTP3 | gain | SYCL no-MTP | SYCL MTP3 | gain |
   |---|---|---|---|---|---|---|
   | ~1k  | 21.4 t/s | 35.6 t/s | **+66%** | 22.5 t/s | 38.5 t/s | **+71%** |
   | ~16k | 13.7 t/s | 14.9 t/s | +9%    | 18.8 t/s | 31.7 t/s | **+69%** |
   | ~32k | 9.8 t/s  | 8.4 t/s  | −14%   | 15.9 t/s | 22.8 t/s | **+43%** |

   At short context MTP is a pure win on both backends (single-row no-draft decode is
   ~21–22 t/s, latency/kernel-bound and *below* the 37 t/s ceiling; MTP batches 4 rows/step
   and reaches it). At depth the per-step cost is dominated by the O(L) attention term, so
   the draft no longer pays for its forward — on Vulkan the gain goes negative. Same root
   cause as (2), not a fault of MTP itself.

## Hypothesis: the scalar flash-attention path does not scale with KV length

`ggml-vulkan` force-selects the **scalar** flash-attention path when there is a single query
row — `n_rows == 1 → FA_SCALAR`, even on coopmat2 devices (`get_fa_tuning_params`). That
means **decode never uses the matrix-core attention**, and the scalar / large-KV FA on Vulkan
degrades roughly linearly with context, unlike SYCL's path. The Vulkan backend also still
lacks the merged Xe2 FA/GEMM improvements (upstream work in progress).

So this looks like a **kernel-maturity gap on the deep-attention path**, not a driver or
quantization issue, and not something the recent matmul commits address (they target the
MM/MMQ batch paths and other weight types).

## Control: RDNA3 does not show the collapse

For contrast, a third-party single-run benchmark on **RX 7900 XTX (Navi31 / gfx1100)** with a
near-identical setup (Qwen-27B GGUF + MTP, 32k context, 28k prompt + 2000-token long output,
q8_0 KV, FA on) reports **Vulkan decode holding ~58–60 t/s at 28–30k depth** — i.e. it does
*not* collapse, and is in fact faster than our B70 short-context peak. (Source:
[hcgdw/rx-7900-xtx-llm-benchmark](https://github.com/hcgdw/rx-7900-xtx-llm-benchmark); single
run, not a per-depth scan — we treat it as directional.)

Possible reasons RDNA3 is immune: RADV has a fused flash-attention path for symmetric KV
quant (bit-packing), and the `n_rows==1 → FA_SCALAR` trap may not apply the same way on RADV.
We have a 7900 XTX on order and will run the **same per-depth scan** to confirm — happy to
add those numbers here when the card arrives.

## What we can offer

- The `depth_scan.py` runner + raw JSON for every row above (B70 Vulkan q8/f16, B70 SYCL,
  no-draft controls) — available in our repo if useful for reproduction.
- Willing to run `GGML_VK_PERF_LOGGER=1`, A/B the FA path, or test a patched
  `get_fa_tuning_params` (e.g. not forcing FA_SCALAR at n_rows==1 on coopmat2 devices) to
  isolate the kernel.

## Environment

- llama.cpp b10883 (Vulkan build) / v0.4.0 (SYCL build)
- Mesa 26.2.2 (kisak PPA, ANV) for Vulkan; oneAPI c26.31 for SYCL
- Ubuntu 26.04 host, `xe` kernel driver (Intel), single Arc Pro B70 at `/dev/dri/renderD128`
