# Vulkan vs SYCL on B70 — why the gap, controlled depth scan (2026-09-10)

Filed upstream: [ggml-org/llama.cpp#28721](https://github.com/ggml-org/llama.cpp/issues/28721).

Question: why is Vulkan much slower than SYCL on our dense Qwen3.8-27B load, even
though b10883 merged several GPU matmul updates and external sources report high
Vulkan token rates?

## Controlled experiment

Same model (`Qwen3.8-27B-Q4_K_M`, 16.4 GB weights), same MTP3 draft (Q8_0,
n-max 3), same sampling, 96-token decode per point, context filled by the
request prompt itself. Two backends on the same Arc Pro B70 (`b70-vulkan-dev`
= llama.cpp b10883 Vulkan/Mesa 26.2.2 kisak ANV; `b70-dev-test-v040` = SYCL
v0.4.0/c26.31). KV q8_0 for both; plus a Vulkan f16-KV control.

| depth (tokens) | Vulkan q8_0 KV dec | Vulkan f16 KV dec | SYCL q8_0 KV dec | Vulkan TTFT | SYCL TTFT |
|---|---|---|---|---|---|
| ~1k    | 35.6 t/s | 33.4 t/s | 38.5 t/s | 1.8s | 1.8s |
| ~15k   | 14.9 t/s | 13.3 t/s | 31.7 t/s | 43.2s | 23.2s |
| ~32k   | 8.4 t/s  | 8.2 t/s  | 22.8 t/s | 94.1s | 28.5s |
| ~64k   | 4.5 t/s  | 4.3 t/s  | 15.8 t/s | 329.0s | 64.9s |

Raw data: `benchmark/results/depthscan-{vulkan-q8kv,vulkan-f16kv,sycl-q8kv}.json`,
runner `benchmark/depth_scan.py`.

## Findings

1. **Short-context decode: Vulkan is NOT meaningfully slower.** 35.6 vs
   38.5 t/s (-8%). Both are at the memory-bandwidth limit: dense 27B reads
   ~16.4 GB of weights per token; B70's 608 GB/s GDDR6 => ~37 t/s theoretical.
   There is no headroom for kernel micro-optimization here — this is why
   b10883's matmul updates (#25773 spec-constant A-type, #27471 f16 B-type
   pipelines / Intel warp-tile tuning) changed nothing measurable for our
   short-context t1/t2 (35.5-38.8 t/s on both v0.4.0 and b10883).

2. **External "high token rates" are a different workload.** 60-76 t/s
   reports are sparse MoE (Qwen3.6-35B-A3B, ~3 GB active/token) or small dense
   models (8B), or pre-Mesa-26.1 comparisons. A public B70 dense-27B Vulkan
   measurement (jonathanmann.tech) got ~20 t/s — below ours. Our 35-39 t/s
   short-context is at/above that class of result. The Mesa 26.0->26.1 ~2x
   decode jump (discussion #27777, B580) is already inside our image (Mesa
   26.2.2) and is not coopmat2 (that thread showed GGML_VK_DISABLE_COOPMAT2
   changed nothing on the 26.1 driver).

3. **The real gap is deep-context scaling, and it is backend-intrinsic on
   Vulkan.** Vulkan decode drops ~8x from 1k to 64k (35.6 -> 4.5 t/s); SYCL
   drops only ~2.4x (38.5 -> 15.8). Prefill: Vulkan TTFT explodes (562 ->
   101 t/s effective prefill at 64k; 329s for a 33k-token prompt) while SYCL
   holds ~510-635 t/s all the way down. Agent workloads (t3 with 50-75k ctx:
   5-9 vs 16-18 t/s) are dominated by this regime.

4. **KV quantization is NOT the cause.** Vulkan with f16 KV collapses
   identically (33.4 -> 4.3 t/s). (Note: unrelated folklore on quantized KV
   at depth is about other stacks; on this backend the collapse reproduces
   with f16 KV.) Draft acceptance is also not the cause (acc 0.47-0.68 on
   both; SYCL's acc is lower at depth yet still decodes much faster).

5. **Likely root cause: Vulkan attention kernels do not scale with KV
   length.** ggml-vulkan force-selects the scalar flash-attention path when
   there is a single query row (`n_rows == 1` -> FA_SCALAR even on coopmat2
   devices, `get_fa_tuning_params`), i.e. decode never uses the matrix-core
   attention; and the scalar/large-KV FA on Vulkan degrades roughly linearly
   with context, unlike SYCL's path. The Vulkan backend also still lacks the
   merged Xe2 FA/GEMM improvements (upstream work in progress). This is a
   kernel-maturity gap, not a driver or quantization issue, and not
   addressable by the recent matmul commits (they target the MM/MMQ batch
   paths and other weight types).

## Bottom line

- Short-context dense-27B: Vulkan ~= SYCL (both at the DRAM ceiling); the
  "Vulkan is slow" perception comes from deep-context agent loads.
- Dense 27B is intrinsically ~37 t/s at 608 GB/s on this card regardless of
  backend; prefer MoE models for raw throughput.
- Expect real Vulkan gains only when upstream lands Xe2 flash-attention /
  GEMM work; the b10883 matmul commits do not move our dense short-context
  decode (no headroom) nor the deep-context attention path.
- Re-test recipe: `benchmark/depth_scan.py` (per-KV/backend rows above).
## Addendum: does MTP increase token rate? (measured)

MTP3 (Q8_0 draft, n-max 3, p-min 0.10) vs no-draft, same depth scan, 96-token
decode. `predicted_per_second` = accepted main-model output tokens.

| depth | Vulkan no-MTP | Vulkan MTP3 | gain | SYCL no-MTP | SYCL MTP3 | gain |
|---|---|---|---|---|---|---|
| ~1k  | 21.4 t/s | 35.6 t/s | **+66%** | 22.5 t/s | 38.5 t/s | **+71%** |
| ~16k | 13.7 t/s | 14.9 t/s | +9% | 18.8 t/s | 31.7 t/s | **+69%** |
| ~32k | 9.8 t/s  | 8.4 t/s  | -14% | 15.9 t/s | 22.8 t/s | **+43%** |

Data: `benchmark/results/depthscan-{vulkan,sycl}-nodraft.json`.

- **MTP genuinely increases token rate**: +66-71% at short context on BOTH
  backends (single-row no-draft decode is ~21-22 t/s, latency/kernel-bound and
  BELOW the 37 t/s bandwidth ceiling; MTP batches 4 rows/step and reaches the
  ceiling). Our 35-39 t/s t1/t2 numbers already include this MTP gain.
- **The MTP gain collapses with depth on Vulkan only**: +66% -> +9% -> -14%
  (1k->16k->32k), while SYCL keeps +71% -> +69% -> +43%. At depth the
  per-step latency is dominated by the O(L) attention cost (Vulkan's weak
  deep-attention path) plus the fixed draft forward; draft acceptance also
  drops with depth (0.68->0.47), so the draft no longer pays for its latency.
  This is another expression of the same root cause (deep-attention scaling),
  not a fault of MTP itself.
- Practical upshot: keep MTP3 for short-context work on both backends; for
  deep-context agent loops on Vulkan, MTP3 is neutral-to-harmful until the
  deep-attention path improves upstream.
