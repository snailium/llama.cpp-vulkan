# Benchmark results

One file per dated test run: `YYYY-MM-DD-<card>-<config-slug>.md`. Format and rules in [`../METHODOLOGY.md`](../METHODOLOGY.md).

## Reports

| Date | Report | Card | Notes |
|---|---|---|---|
| 2026-09-10 | [Long-context agentic decode — per-depth scan](2026-09-10-long-context-agentic-depth-scan.md) | B70 (Vulkan vs SYCL) + RDNA3 control | Headline: Vulkan deep-context decode collapses ~8x; RDNA3 does not. Raw JSON below. |
| 2026-09-10 | [Vulkan v0.4.0](2026-09-10-vulkan-v040.md) · [Vulkan dev b10883](2026-09-10-vulkan-dev-b10883.md) | B70 | T1–T5 suite + session perf. |

Raw per-depth scan JSON: `depthscan-{vulkan-q8kv,vulkan-f16kv,sycl-q8kv,vulkan-nodraft,sycl-nodraft}.json` (runner [`../depth_scan.py`](../depth_scan.py)).

> 7900 XTX numbers are pending hardware arrival — the per-depth scan will be re-run on RDNA3 and added here.
