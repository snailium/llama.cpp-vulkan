# Benchmark results

One file per dated test run: `YYYY-MM-DD-<card>-<config-slug>.md`. Format and rules in [`../METHODOLOGY.md`](../METHODOLOGY.md).

## Reports

| Date | Report | Card | Notes |
|---|---|---|---|
| 2026-09-10 | [Long-context agentic decode — per-depth scan](2026-09-10-long-context-agentic-depth-scan.md) | B70 (Vulkan vs SYCL) + RDNA3 control | Headline: Vulkan deep-context decode collapses ~8x; RDNA3 does not. Raw JSON below. |
| 2026-09-10 | [Vulkan v0.4.0](2026-09-10-vulkan-v040.md) · [Vulkan dev b10883](2026-09-10-vulkan-dev-b10883.md) | B70 | T1–T5 suite + session perf. |
| 2026-09-23 | [XTX context ceiling](2026-09-23-xtx-context-ceiling.md) | 7900 XTX (Vulkan) | Headline: real ceiling is ~287 K, not the configured 128 K; cliff at 292864→293888 collapses decode 6.5x while free VRAM *increases*. |
| 2026-09-23 | [B70 deep-context collapse fixed in b11117](2026-09-23-b70-deep-context-collapse-fixed.md) | B70 (Vulkan) | Headline: 64 K depth decode 4.5→24.0 t/s vs b11064. |

Raw per-depth scan JSON: `depthscan-{vulkan-q8kv,vulkan-f16kv,sycl-q8kv,vulkan-nodraft,sycl-nodraft}.json` (runner [`../depth_scan.py`](../depth_scan.py)).

> The 7900 XTX context-ceiling scan is in (2026-09-23); a per-depth scan on RDNA3 is still pending.
