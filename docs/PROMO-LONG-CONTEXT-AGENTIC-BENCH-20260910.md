# 全网没人测的，恰恰是真正卡住 agent 的那一项

**单张 B70 / RDNA 卡上，llama.cpp 长上下文 agentic 解码逐深度实测**

> 中文为主 · 英文摘要在文末 · 数据与方法论可复现 · 2026-09-10

---

## TL;DR（30 秒版）

我们在一张 **Intel Arc Pro B70**（工作站卡，32 GB）上跑了 llama.cpp 的 **Vulkan vs SYCL**，
用一个真实 agent 会话的方式**逐深度扫 decode 速率**。结论：

- **短上下文 Vulkan 和 SYCL 基本打平**（35.6 vs 38.5 t/s，差 8%），都在带宽天花板。
- **深上下文 Vulkan 塌了 ~8 倍**（1k→64k：35.6 → 4.5 t/s），SYCL 只掉 ~2.4 倍。
- **不是 KV 量化的锅**——f16 KV 同样塌；也不是 MTP 的锅。
- **RDNA3（RX 7900 XTX）不塌**——第三方实测 Vulkan 在 28–30k 深度还保持 ~58–60 t/s。

一句话：**"Vulkan 慢"是错觉，真正慢的是"B70 上的 Vulkan 跑长上下文 agent"**。这是
backend-intrinsic（驱动/内核成熟度）问题，不是你的配置问题。

---

## 为什么这个测试重要

2026 年 agentic inference benchmark 才刚立起来：[MLPerf Agentic Inference](https://mlcommons.org/2026/07/agentic-inference-for-mlperf-inference/)
（7 月）、[SemiAnalysis AgentX](https://inferencex.semianalysis.com/blog/agentic-benchmark-agent-benchmark-guide)、
[AgentSysBench (arxiv)](https://arxiv.org/html/2608.15127)。它们都承认"context 会随 trajectory
增长 → prefill/KV 压力上升"。

**但它们测的全是数据中心 serving 集群**：vLLM/SGLang/TRT-LLM + B200/MI300X，指标是
Pareto 曲线（并发多少 agent、成本几何）。continuous batching + prefix caching + KV offload
这些机制**恰恰把"单个会话 KV 涨大导致 decode 变慢"这个效应摊薄/掩盖了**。

而 llama.cpp 是单进程、基本单会话的后端，没有这些遮羞布——它**诚实地暴露了原始 kernel
行为**。但 benchmark 世界根本不测 llama.cpp，也不测消费级/prosumer 卡。

**中间没人做"单张 Arc/AMD 卡上真实 growing-KV agent 会话的逐深度 decode 曲线"**。我们补上了。

---

## 方法（可复现）

每个深度发一个 chat 请求：user message 当 KV filler（prefill），然后 **96-token decode**，
从流式响应的 `timings` 读速率。同模型、同 MTP3 draft、同采样、同 KV 类型跨后端对比。

- 模型：`Qwen3.8-27B-Q4_K_M`（dense，16.4 GB）+ MTP3 Q8_0 draft
- 卡：Intel Arc Pro B70（32 GB，BMG-G31 / Xe2），单卡全 offload
- 后端：`b10883 + Vulkan / Mesa 26.2.2 (kisak ANV)` vs `SYCL v0.4.0 / c26.31`
- KV：q8_0（另加 f16 KV 对照）
- Runner：[`depth_scan.py`](https://github.com/snailium/llama.cpp-vulkan/blob/main/benchmark/depth_scan.py)

## 结果：decode t/s 随上下文深度

| 深度 (tokens) | Vulkan q8_0 KV | Vulkan f16 KV | SYCL q8_0 KV | Vulkan TTFT | SYCL TTFT |
|---|---|---|---|---|---|
| ~1k   | **35.6** | 33.4 | 38.5 | 1.8 s   | 1.8 s   |
| ~15k  | **14.9** | 13.3 | 31.7 | 43.2 s  | 23.2 s  |
| ~32k  | **8.4**  | 8.2  | 22.8 | 94.1 s  | 28.5 s  |
| ~64k  | **4.5**  | 4.3  | 15.8 | 329.0 s | 64.9 s  |

**Prefill 也只在 Vulkan 上塌**：有效 prefill 从 562 → 101 t/s（1k→64k），33k prompt 的
TTFT 高达 **329 秒**；SYCL 全程保持 ~510–635 t/s。

## 关键发现

1. **短上下文不是问题。** 35.6 vs 38.5（−8%），都在 608 GB/s 带宽天花板（dense 27B 每 token
   读 ~16.4 GB → 理论 ~37 t/s）。没余量，所以 b10883 那几个 matmul commit 对短上下文 decode
   毫无影响——这不是 bug，是物理极限。

2. **塌陷是 backend-intrinsic。** f16 KV 同样塌（排除 KV 量化）；draft acceptance 两边都
   0.47–0.68、SYCL 在深度还更低却更快（排除 MTP）。根因指向 `ggml-vulkan` 在 `n_rows==1`
   时强制走 **scalar flash-attention**（`get_fa_tuning_params`），解码永远用不上 matrix-core
   attention，scalar/大 KV 的 FA 随上下文近似线性退化。内核成熟度差距，不是驱动或量化问题。

3. **MTP 增益在 Vulkan 上随深度蒸发**（no-draft 对照）：+66%→+9%→−14%（1k→16k→32k），
   SYCL 保持 +71%→+69%→+43%。短上下文 MTP 两边都纯赚（单行无 draft decode 只有 ~21–22 t/s，
   延迟绑定、低于天花板；MTP 把每步变 4 行批量才拉满）。

## RDNA3 对照：7900 XTX 不塌

第三方单次运行（[hcgdw/rx-7900-xtx-llm-benchmark](https://github.com/hcgdw/rx-7900-xtx-llm-benchmark)），
配置几乎相同（Qwen-27B GGUF + MTP，32k ctx，28k prompt + 2000-tok 长输出，q8_0 KV，FA on）：
**Vulkan decode 在 28–30k 深度保持 ~58–60 t/s**——不塌，还比我们 B70 短上下文峰值快。
（单次运行、非逐深度扫描，作方向性参考。）我们 7900 XTX 到货后会跑同一套逐深度扫描补上曲线。

## 给 B70 / RDNA 用户的实操建议

- **短上下文 dense 工作**：Vulkan ≈ SYCL；MTP3 保持开（纯 +66–71%）。
- **B70/Vulkan 深上下文 agent 循环**：预期会塌；深度上 MTP3 中性甚至有害，等上游 Xe2 FA/GEMM
  落地。要吞吐就选 MoE，必须 dense 就上 SYCL。
- **7900 XTX / RDNA3**：无塌陷证据，Vulkan 是一等公民路径。注意 Mesa/RADV ≥ 25.3 + ReBAR 开启。

## 复现

```bash
export DEPTH_SCAN_URL=http://<your-server>/v1
export MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
export KV_LABEL=vulkan-q8kv
export DEPTHS=1024,15360,32768,65536
python3 benchmark/depth_scan.py   # → benchmark/results/depthscan-<KV_LABEL>.json
```

完整报告：[`benchmark/results/2026-09-10-long-context-agentic-depth-scan.md`](https://github.com/snailium/llama.cpp-vulkan/blob/main/benchmark/results/2026-09-10-long-context-agentic-depth-scan.md)
· 研究写up：[`docs/VULKAN-PERF-RESEARCH-20260910.md`](https://github.com/snailium/llama.cpp-vulkan/blob/main/docs/VULKAN-PERF-RESEARCH-20260910.md)

---

## English abstract

**Nobody benchmarks the thing that actually hurts agent sessions on consumer/prosumer GPUs.**
We ran llama.cpp **Vulkan vs SYCL** on a single **Intel Arc Pro B70**, sweeping decode
throughput **per context depth** (the way a real agent session grows its KV cache). Findings:

- Short-context decode is fine: Vulkan 35.6 vs SYCL 38.5 t/s (−8%), both at the 608 GB/s ceiling.
- **Deep-context decode collapses ~8x on Vulkan** (1k→64k: 35.6 → 4.5 t/s); SYCL only ~2.4x.
- Not a KV-quant effect (f16 KV collapses identically), not an MTP artifact.
- **RDNA3 (RX 7900 XTX) does not collapse** — third-party data shows Vulkan holding ~58–60 t/s at 28–30k depth.

Root cause points to `ggml-vulkan` forcing the **scalar flash-attention path at `n_rows==1`**
(`get_fa_tuning_params`), so decode never uses matrix-core attention and degrades ~linearly with
context — a kernel-maturity gap, not a driver or quantization issue.

The 2026 agentic-inference benchmarks (MLPerf Agentic Inference, SemiAnalysis AgentX) measure
**datacenter serving clusters** with batching engines that *mask* per-session KV-growth cost.
llama.cpp on a single consumer card is the honest baseline they can't show — and nobody had
published it. We do. Reproduction runner + raw JSON in the repo.
