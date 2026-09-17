# KV Precision Comparison: B70 SYCL q8_0 vs XTX Vulkan q4_0

**Date:** 2026-09-16
**Model:** Qwen3.8-27B-Q4_K_M (identical weights on both backends)
**Sampling:** temperature 0.7, top_p 0.80, top_k 20, min_p 0.0, presence_penalty 1.5 (both identical)

## TL;DR

**No measurable quality difference between q8_0 KV (B70/SYCL) and q4_0 KV (XTX/Vulkan).**
The XTX q4_0 KV + Q4_0 MTP draft configuration is safe for our workload classes
(retrieval QA, code generation, agent tool-calling). The VRAM savings are a net win.

## Setup

| | B70 | XTX |
|---|---|---|
| GPU | Intel Arc Pro B70 (32 GB) | AMD RX 7900 XTX (24 GB) |
| Backend | SYCL (oneAPI) | Vulkan |
| KV cache quant | **q8_0** | **q4_0** (fits 24 GB) |
| MTP draft quant | Q8_0 (MTP4) | Q4_0 (MTP4) |
| Weight quant | Q4_K_M | Q4_K_M |

XTX is at 24 GB VRAM; q8_0 KV would not leave enough headroom, hence the downgrade.
B70 has 32 GB and keeps q8_0 as the quality reference.

## Method

`benchmark/kv_probe.py` (commit `cc59677`): four deterministic task families,
same weights, same sampling, scored by exact match:

- **A. Needle-in-20k-context** — 20k-token filler document, fact planted at the very
  start (`ZEBRA-7741`), model must recall it verbatim.
- **B. Arithmetic** — 6 three-digit additions, answer with just the number.
- **C. Code generation** — Python function `f(x) = x^2 + 3`, docstring example value
  must be numerically correct.
- **D. Entity recall** — verbatim fact + key-value extraction.

n=10 samples per task per backend (plus targeted re-runs of every miss).

## Results (n=10)

| Task | SYCL q8_0 | Vulkan q4_0 |
|---|---|---|
| A. needle 20k | 10/10 | 10/10 |
| B. arithmetic | 9/10 | 8/10 |
| C. code | 9/10 | 10/10 |
| D. entity | 10/10 | 10/10 |

### The misses are model-level, not quantization-level

Every B-class miss was re-run on both backends: the same instance
(`915+160+878+878+302+983`) is answered **wrong identically on both** (both say 5116).
This is a Qwen3.8-27B weakness in long-chain arithmetic, independent of KV precision.
The other B70 miss flipped to correct on re-sample.

### 20k-context stress check

Combined needle + arithmetic request after a full 20k-token context: both backends
produce **byte-identical answers** (ZEBRA-7741 / 3802). No recall degradation from
q4_0 KV at 20k depth.

## Why the difference is so small

1. **KV quantization is a "soft" loss.** q4_0 compresses K/V from 8-bit to 4-bit
   (per-channel scale); it loses attention mantissa precision, not structural
   information. A 27B model tolerates this far better than weight quantization.
   Community consensus: KV q4_0 is near-lossless for most tasks; only extreme
   long-context needle / multi-hop reasoning starts to expose a gap.
2. **MTP draft quant affects speed, not quality.** Speculative decoding drafts are
   verified token-by-token by the target model — rejected drafts are discarded and
   generation falls back. Output distribution is fully determined by the Q4_K_M
   main weights + KV precision. MTP draft quant only moves decode speed (acceptance
   rate), never output quality.
3. **The real quality floor is the weight quant (Q4_K_M).** KV/MTP precision choices
   are second-order adjustments on top of that floor.

## Practical guidance

- **Our workload classes (retrieval QA, code gen, agent tool-calling):** q4_0 KV is
  safe to use. The VRAM savings (roughly half the KV memory vs q8_0) buy larger
  context headroom — a net win for agent scenarios.
- **Where q4_0 KV could start to matter:** very long context + multi-hop exact
  reasoning (64k+ document QA, chained math proofs). But in that regime the B70
  FA_SCALAR decode collapse (issue #28721) becomes the binding constraint first, so
  priority does not change.

## Reproduction

```bash
cd llama.cpp-vulkan
KV_PROBE_N=10 python3 benchmark/kv_probe.py   # ~20-30 min for n=10 on both backends
```

Requires both backends healthy: `b70-sycl` :18080, `xtx-vulkan` :18090.
