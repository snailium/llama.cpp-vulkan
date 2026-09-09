# Benchmark Methodology (Vulkan repo)

This document defines the test methodology used by every report under `benchmark/results/`. It is **mirrored from the sibling SYCL repo** ([`snailium/llama.cpp-sycl-intel-b70`](https://github.com/snailium/llama.cpp-sycl-intel-b70), `benchmark/METHODOLOGY.md`) so that numbers are directly comparable across backends (SYCL vs Vulkan) and across cards (B70 vs 7900 XTX).

> Reference: benchmarks measure **llama.cpp + Vulkan** running **Qwen3.8-27B (Q4_K_M)** on a single **Intel Arc Pro B70** (32 GB, BMG-G31) **or** a single **AMD Radeon RX 7900 XTX** (24 GB, RDNA3). For backend-to-backend comparisons (SYCL, ROCm, vLLM), only the contended metrics in this document are used.

## 1. Workload and environment

- **Model stack (ggml-org):**
  - Main model: `Qwen3.8-27B-Q4_K_M.gguf` (≈18.9 GB)
  - Multimodal projector: `mmproj-Qwen3.8-27B-BF16.gguf` (when vision tasks are run)
  - MTP draft (when speculative mode is used): `mtp-Qwen3.8-27B-Q4_0.gguf` / `-Q8_0.gguf`
- **GPU:** Intel Arc Pro B70 (32 GB) and/or AMD RX 7900 XTX (24 GB). One GPU per run; record the `vulkaninfo --summary` `driverInfo` line.
- **Server:** `llama.cpp-vulkan:server` container, OpenAI-compatible endpoint at `:8080/v1`.
- **Host state recorded in every report:** kernel version, host Mesa (if any ICD is host-provided), container image digest, offload line from the server log.

## 2. The five-task test suite (T1–T5)

Identical to the SYCL repo so results compare across backends:

| ID | Task | Type | Notes |
|----|------|------|-------|
| T1 | Historical **HTML** page | Direct API, single-shot | Dense generation artifact; must close all tags |
| T2 | Big-Bang **SVG** artwork | Direct API, single-shot | Large structured artifact; must be complete |
| T3 | Security review of an MQTT→Home Assistant bridge | Agent (tool use) | Long, multi-tool reasoning chain |
| T4 | Host system config **JSON** report | Agent (tool use) | Requires real host data via tools |
| T5 | Ottawa YOW snowfall research | Agent (tool use) | Long research task; cross-validated sources |

- **T1/T2** are single-generation artifact tasks hit over the OpenAI-compatible endpoint (no tools).
- **T3/T4/T5** are agentic workloads run through an external agent harness that substitutes real tool calls for the model's tool invocations, exercising long, continuously growing context.

**Thinking mode must be OFF for all artifact tasks** (`chat_template_kwargs.enable_thinking=false`).

## 3. Metrics and how they are measured

| Metric | Definition / Source | Caveat |
|--------|---------------------|--------|
| **Decode t/s** | Token generation rate; read from the **streamed `tg`** field or single-shot `timings` | Do **not** use llama.cpp's logged `eval time ... / N tokens` as the user-facing rate — it is a batched figure and can be inflated. |
| **Prompt (prefill) t/s** | Prompt processing throughput | Varies strongly with context length and KV-cache hits. |
| **Wall-clock per call** | End-to-end for a representative agent-shaped call (e.g. 8K prompt + 1K completion) | The number users actually feel. |
| **Aggregate t/s (N streams)** | Total tokens/s across N concurrent single-stream clients | Where B70 Vulkan is expected to shine vs SYCL. |
| **Draft acceptance** (MTP runs) | Accepted/total proposed draft tokens | Below ~0.3 the draft is a net slowdown. |
| **Free VRAM before run** | From the loader log / `vulkaninfo` | Guards against the partial-offload trap. |

## 4. Rules that apply to every report

1. Verify with a real `/v1/chat/completions` → `finish_reason=stop`.
2. Thinking **off** for artifact tasks.
3. Read the offload line (`n_gpu_layers=…`) before trusting any number (see `docs/VULKAN-TUNING.md` §5).
4. KV type per card: B70 f16 default / q8_0 with draft+large ctx; 7900 XTX q8_0 for ≥32k (see `docs/VULKAN-KNOWLEDGE.md` §7).
5. Three seeds per config where the metric is a rate (driver-level variance is real — see the Mesa A/B methodology in discussion #27777).
6. Record host + container state (kernel, driverInfo, image digest) in the report header.

## 5. Report format

One file per dated run under `benchmark/results/`, named `YYYY-MM-DD-<card>-<config-slug>.md` (e.g. `2026-09-10-b70-f16-96k.md`). Structure: header (env + image digest + offload line) → config table → T1–T5 results → metric tables → notes/anomalies. See the SYCL repo's reports for worked examples.
