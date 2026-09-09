# Project Status

**Focus:** an up-to-date llama.cpp + **Vulkan** Docker image that serves **both** the Intel Arc Pro B70 (32 GB, Battlemage) and the AMD Radeon RX 7900 XTX (24 GB, RDNA3) from a single binary.

> **State: EARLY.** The image builds cleanly against upstream llama.cpp master with `GGML_VULKAN=ON`. **No hardware benchmark has been run yet** — this repo was scaffolded as the Vulkan sibling of [`llama.cpp-sycl-intel-b70`](https://github.com/snailium/llama.cpp-sycl-intel-b70). Everything below "Verified working" is *expected from public data*, not measured here.

## Current default pins in `.devops/vulkan.Dockerfile`

| Component | Version | Notes |
|-----------|---------|-------|
| Base image | `ubuntu:26.04` | Distro archive provides the ICDs |
| Mesa (reference pin) | `26.1.7` | **Build fails** if distro `mesa-vulkan-drivers` < this (the ANV cooperative-matrix fix lives in 26.1.x) |
| Vulkan loader | distro `libvulkan1` | Matches distro GL/GLVND stack |
| ICDs | `mesa-vulkan-drivers` (ANV + RADV) | One package, both cards |
| llama.cpp | upstream master (subtree) | CI tracks `v*` tags on `main`, latest `b*` on `dev` |
| GGML_VULKAN | `ON` | |
| GGML_BACKEND_DL | `ON` | Dynamic backend loading |
| GGML_CPU_ALL_VARIANTS | `ON` | CPU fallback coverage |
| Web UI build | `OFF` by default (`BUILD_WEBUI=0`) | Server-only image |

**Driver model:** host kernel driver (`xe` / `amdgpu`) does DMA; the container ships only the user-space ICDs. This is the standard low-friction Vulkan deployment and means **host Mesa/kernel updates can change performance without any image rebuild** — verify `vulkaninfo --summary` on the host before benchmarking (see `docs/VULKAN-TUNING.md` §2).

## Verified working

- Image builds (`server`, `light`, `full` targets) against upstream llama.cpp master with Vulkan + dynamic backends + all CPU variants.
- Mesa pin-check at build time fails loudly on a regressed distro archive.
- **That's it.** No GPU has been run through this image yet.

## Expected (from public data — to be confirmed here)

- **B70:** post-Mesa-26.1 Vulkan decode ≈ 2× pre-26.1; at concurrency Vulkan ≥ SYCL; single-stream dense prefill possibly still behind SYCL+oneDNN/XMX. Sources: [ggml-org/llama.cpp#27777](https://github.com/ggml-org/llama.cpp/discussions/27777) (B580, same family), [B70 field report](https://jonathanmann.tech/blog/intel-arc-b70-llama-cpp-benchmarks/).
- **7900 XTX:** Vulkan ≈ ROCm for token generation, simpler ops. Sources: [1337hero/rx7900xtx-llama-bench-vulcan](https://github.com/1337hero/rx7900xtx-llama-bench-vulcan), [ROCm-vs-Vulkan](https://aguyintech.com/rocm-vs-vulkan-on-the-rx-7900-xtx/).
- f16 KV holds up at depth on B70 Vulkan; q8_0 KV required for MTP + large context (carried over from the SYCL repo's 32 GB math — re-verify on Vulkan).

## Known risks / open questions

1. **Mesa in the container vs host ICD.** The image ships `mesa-vulkan-drivers`, but if the host exposes its own ICD via `/usr/share/vulkan/icd.d` and we mount it, the host driver wins. Decide the canonical model (container ICD only) and document it; `VK_DRIVER_FILES` is the escape hatch.
2. **B70 prefill gap.** If SYCL+XMX still wins dense prefill by a lot, some workloads may want *both* images — that's fine, but say so in docs once measured.
3. **7900 XTX context ceiling.** 24 GB: Q4_K_M 27B (≈18.9 GB) + KV leaves little room; the recommended max context for 27B-class is untested here.
4. **Speculative/MTP on Vulkan.** Upstream supports it, but no B70/7900XTX numbers exist in this repo yet — first benchmark should include a draft-model run.

## How to help (priority order)

1. **Run the T1–T5 suite on a real B70** with `examples/b70-server.sh` and file the report under `benchmark/results/`.
2. **Run the same on a real 7900 XTX** (`examples/7900xtx-server.sh`).
3. Mesa pin updates when ANV/RADV ship perf fixes (CI also tracks this).
4. Incident reports (GPU dropouts, partial-offload misreads, driver regressions) → `benchmark/incidents/`.

Last updated: 2026-09-08 (initial scaffold).
