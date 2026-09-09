# Benchmark configs

One file per reproducible server configuration. Each config states the card, backend knobs, and *why* each value is chosen; every one links to its launcher in `examples/`.

| Config | Card | Status |
|--------|------|--------|
| [`b70-f16-96k.md`](./b70-f16-96k.md) | B70, f16 KV, 96k, no draft | expected — unverified |
| [`b70-mtp3-q4-96k.md`](./b70-mtp3-q4-96k.md) | B70, MTP3 + Q4_0 draft, f16 KV, 96k | expected — first-priority experiment |
| [`7900xtx-q8-32k.md`](./7900xtx-q8-32k.md) | 7900 XTX, q8_0 KV, 32k, no draft | expected — unverified |

Add a new config file (same structure) before running a new combination; reference it from the resulting report in `../results/`.
