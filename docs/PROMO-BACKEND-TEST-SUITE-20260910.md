# 同一模型、同一套 prompt，把后端的真实性能一次测全

**B70 / RDNA 单卡上的 llama.cpp 后端全量测试套件（t1–t5 + V1–V3）——含 agentic 工具调用任务**

> 中文为主 · 英文摘要在文末 · 数据可复现 · 2026-09-10

---

## TL;DR（30 秒版）

我们做了一套**固定模型 + 固定 prompt** 的后端测试套件，跑在单张 **Intel Arc Pro B70**
（工作站卡，32 GB）上，一次测出后端的**完整性能画像**——不只是"快不快"，还有"对不对"：

- **t1–t5**：长文生成 + 三个真实 agentic 任务（代码安全审查 / 主机配置 JSON / 历史降雪量计算），
  通过真实 agent harness 带工具调用跑。
- **V1–V3**：视觉读图（游戏截图 / 主板点位图 / 轮胎侧壁）。
- **同一模型、同一套 prompt、同一采样**，换后端（SYCL vs Vulkan）就能直接对比。

2026 年的 agentic inference benchmark（MLPerf、SemiAnalysis InferenceX/AgentX、Applied Compute）
**全在测数据中心 serving 集群**（vLLM/SGLang/TRT-LLM + B200/MI300X，多并发、Pareto 曲线）。
**没人用固定模型 + 固定 prompt 套件，在单张 prosumer 卡上同时测出"性能 + 正确性"的后端全量画像。**
我们补上了。

---

## 为什么是"同一模型 + 同一套 prompt"

对比后端时最大的坑是**变量不隔离**：换模型、换量化、换 prompt、换采样，结果就没法比了。
我们的规则很简单——**除了后端（SYCL/Vulkan/KV 量化/MTP 配置），其它一律不动**：

- 模型固定：`Qwen3.8-27B-Q4_K_M`（dense，16.4 GB）+ MTP3 Q8_0 draft
- prompt 固定：t1–t5 + V1–V3 的原始中文 prompt 一字不改
- 采样固定：temp 0.7 / top-p 0.80 / top-k 20 / presence 1.5（Qwen 官方推荐）
- thinking 全关：`--reasoning off` + `chat_template_kwargs.enable_thinking:false`

这样换后端跑一遍，**差异就只剩后端本身**。这是可复现基线，不是单次玄学。

## 测试套件长什么样

| 任务 | 内容 | 考什么 |
|---|---|---|
| **t1_html** | 生成 996–1024 年世界大事 HTML（~5K tok） | 长文完整生成、有效 HTML |
| **t2_svg** | 生成解释大爆炸的 SVG（~7K tok） | 长文完整生成、有效 SVG |
| **t3_security** | 对 `mqtt2ha` 代码库做安全审查（最长最难） | agentic：多轮 + 工具，深上下文 |
| **t4_hostinfo** | 报告宿主机配置为 JSON（CPU/内存/磁盘/GPU） | agentic：内容必须匹配真机、不幻觉 |
| **t5_snowfall** | 算 YOW 机场历史降雪总量 + 方法 | agentic：数字可复现、单位对得上原始 API |
| **V1–V3** | 游戏截图 / 主板点位图 / 轮胎侧壁读图 | 视觉：准确读取、不编造被遮挡部分 |

t3/t4/t5 不是直接 HTTP 调用——它们走一个**真实 agent harness**（隔离的 dsh-container，
不碰生产环境），模型真的发工具调用、收工具输出、再基于累积上下文继续生成。这才是 agentic
工作负载的真实形状：多轮、KV 持续增长、短输出请求密集、tool 之间有停顿。

## 结果：SYCL vs Vulkan（同一模型 + prompt）

| 任务 | 状态 | Vulkan v0.4.0 | SYCL v0.4.0 | 备注 |
|---|---|---|---|---|
| t1_html | PASS | TTFT 0.90s · **38.8 t/s** · acc 0.815 | TTFT 0.94s · 44.8 t/s | 完整有效 HTML（4233 tok） |
| t2_svg | PASS | TTFT 0.84s · **37.8 t/s** · acc 0.896 | TTFT 0.96s · 46.0 t/s | 完整有效 SVG（6597 tok） |
| t3_security | PASS | prefill 110 · **dec 5.6 t/s** · 26.5 min | prefill 430 · 22.3 t/s · 7.4 min | 完整审计：2 High + 5 Medium + 4 Low，带文件/行号 |
| t4_hostinfo | PASS | dec **17.8 t/s** · 1m46s | 37.0 t/s · 56s | JSON 与真机完全一致、零幻觉 |
| t5_snowfall | PASS | dec **17.6 t/s** · 44s | 37.2 t/s · 94s | 145.67 cm，单位对原始 API 核验过 |
| V1 game | PASS | E2E 110.2s · dec 22.3 | E2E 109.5s | 必杀技名/等级/伤害/减益/EP 全对 |
| V2 pcb | PASS | E2E 24.8s · dec 37.5 | E2E 18.9s | CPU/DIMM/M.2/PCIE/IO 全列出（XGA 误读，模型级） |
| V3 tire | PASS | E2E 147.1s · dec 27.1 | E2E 140.4s | 255/70R18 ✓ / M+S+3PMSF（118S 误读，单位 OCR 硬极限） |

**两个后端全任务 PASS、EXIT 0、输出正确完整**；Vulkan 全程 RestartCount=0、0 SIGSEGV/OOM/GPF。
注意：性能差异主要在 **t3 深上下文**（Vulkan dec 5.6 vs SYCL 22.3 t/s）——短上下文 t1/t2 两者都在
带宽天花板（~38 t/s）。完整逐深度曲线见[配套报告](#深入)。

## 这套测试和"agentic benchmark"的区别

| | MLPerf / InferenceX(AgentX) / Applied Compute | 我们的后端套件 |
|---|---|---|
| 测的对象 | **serving 系统**（vLLM/SGLang/TRT-LLM + 多卡集群） | **单卡后端**（llama.cpp SYCL/Vulkan） |
| 硬件 | B200 / MI300X / H100（数据中心） | Arc Pro B70 / RX 7900 XTX（工作站/消费） |
| 并发 | 多 agent 并发、Pareto 曲线 | 单会话真实 agent 循环 |
| 指标 | 吞吐、成本、cache hit rate | TTFT / prefill / decode t/s / draft-acc + **正确性** |
| 模型/prompt | 各家不同 | **固定模型 + 固定 prompt**（可复现基线） |

他们的 batching + prefix caching + KV offload 会**摊薄/掩盖单会话 KV 增长的成本**；llama.cpp
单进程基本单会话，没有这些遮羞布——它**诚实地暴露原始 kernel 行为**。两者互补：他们回答
"这套 serving 能扛多少 agent"，我们回答"**这张卡上这个后端跑 agent 到底多快、对不对**"。

## 给 B70 / RDNA 用户的实操结论

- **短上下文 dense**：Vulkan ≈ SYCL（都在带宽天花板）；MTP3 保持开（纯 +66–71%）。
- **深上下文 agent 循环（B70/Vulkan）**：预期会塌（t3 dec 5.6 t/s），等上游 Xe2 FA/GEMM 落地；
  要吞吐选 MoE，必须 dense 就上 SYCL。
- **7900 XTX / RDNA3**：无塌陷证据，Vulkan 是一等公民路径；注意 Mesa/RADV ≥ 25.3 + ReBAR 开启。

## 复现

```bash
# 1) 起被测后端（OpenAI 兼容端点），模型/KV/MTP 按上面固定
# 2) 跑 t1–t5 + V1–V3（隔离 dsh-container harness，不碰生产）
docker pull ghcr.io/snailium/dsh-container/dsh:latest
#    每个任务：docker run --rm -e DSH_MODE=... dsh --profile <test-profile> <task>
# 3) 逐深度 decode 扫描（可选，隔离 deep-context 塌陷）
python3 benchmark/depth_scan.py   # → benchmark/results/depthscan-<label>.json
```

完整方法 + 原始 JSON：[`benchmark/METHODOLOGY.md`](https://github.com/snailium/llama.cpp-vulkan/blob/main/benchmark/METHODOLOGY.md)
· 逐深度报告：[`2026-09-10-long-context-agentic-depth-scan.md`](https://github.com/snailium/llama.cpp-vulkan/blob/main/benchmark/results/2026-09-10-long-context-agentic-depth-scan.md)
· 已提交上游：[ggml-org/llama.cpp#28721](https://github.com/ggml-org/llama.cpp/issues/28721)

---

## English abstract

**One model, one fixed prompt battery → a complete, comparable performance + correctness profile of an inference backend on a single prosumer GPU.**

We run a **fixed-model / fixed-prompt** backend test suite (t1–t5 + V1–V3) on a single
**Intel Arc Pro B70**: long-text generation (HTML/SVG), three real **agentic** tasks with live
tool calls through an isolated agent harness (codebase security audit, host-config JSON, historical
snowfall computation), and vision reading (game screenshot / PCB layout / tire sidewall). With the
model, prompts, sampling, and thinking-mode all held constant, swapping the backend (SYCL vs Vulkan)
isolates **backend-intrinsic** performance — and we measure both **speed** (TTFT / prefill / decode
t/s / draft-acc) and **correctness** (did the agent actually finish the audit, match the real machine,
verify units against the raw API?).

The 2026 agentic-inference benchmarks (MLPerf Agentic Inference, SemiAnalysis InferenceX/AgentX,
Applied Compute) all measure **datacenter serving clusters** (vLLM/SGLang/TRT-LLM on B200/MI300X)
with concurrency sweeps and Pareto curves. Their batching + prefix caching + KV offload *mask* the
per-session KV-growth cost. llama.cpp on a single consumer/prosumer card is the honest baseline they
can't show — and nobody had published a fixed-model/fixed-prompt battery that reports both performance
and correctness on this class of hardware. We do. Reproduction harness + raw JSON in the repo; filed
upstream as [ggml-org/llama.cpp#28721](https://github.com/ggml-org/llama.cpp/issues/28721).
