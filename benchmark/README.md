# Benchmark suite (Vulkan)

- [`METHODOLOGY.md`](./METHODOLOGY.md) — the 5-task test suite (T1–T5), metric definitions, and the rules every report must follow. Mirrored from the SYCL repo so numbers compare across backends.
- [`configs/`](./configs/) — one file per reproducible server configuration (B70 + 7900 XTX).
- [`results/`](./results/) — dated run reports (**empty until the first hardware run**).
- [`incidents/`](./incidents/) — stability / regression incident logs.

> **Testing methodology matters.** Always verify cards with a real `/v1/chat/completions` → `finish_reason=stop`, keep thinking **off** for artifact tasks, read the offload line before trusting any number, and never trust llama.cpp's batched `eval time` figures as the real throughput.
