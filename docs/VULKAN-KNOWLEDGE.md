# Vulkan Backend Field Knowledge — Intel Arc B70 & AMD RX 7900 XTX

This document is the "why" behind every configuration choice in this repo. It is the companion to [`VULKAN-TUNING.md`](./VULKAN-TUNING.md) (the hands-on flags). Sources are listed per section; treat numbers as *reported by those sources*, not measured here, until `benchmark/results/` says otherwise.

## 1. Why Vulkan for two different vendors

The Vulkan backend (`ggml/src/ggml-vulkan`) is the only llama.cpp GPU backend that is **first-class on both** Intel discrete and AMD discrete without vendor-specific toolchains:

| Backend | B70 | 7900 XTX | Friction |
|---------|-----|----------|----------|
| SYCL | ✅ native (oneAPI) | ❌ no AMD support | oneAPI/IGC/compute-runtime version triangle (see the sibling SYCL repo) |
| ROCm | ❌ no Intel support | ✅ native | ROCm pinning vs kernel/distro; some RDNA3 regressions ([ggml issue #20934](https://github.com/ggml-org/llama.cpp/issues/20934)) |
| **Vulkan** | ✅ via Mesa ANV | ✅ via Mesa RADV | **one image, one API, distro drivers** |

The cost: Vulkan performance is **driver-bound**. The llama.cpp commit matters less than the Mesa version for decode on both cards. That is exactly why this repo pins and pin-checks Mesa at build time.

## 2. The driver model (what runs where)

```
host kernel:   xe (Intel) / amdgpu (AMD)   ← DMA, memory management, GPU reset
container:     libvulkan1 (loader) + mesa-vulkan-drivers (ANV + RADV ICDs)
llama.cpp:     ggml-vulkan backend → Vulkan compute shaders (AOT-compiled at build via glslc,
               first-use per device cached in ~/.cache/llama.cpp)
```

Consequences:

- **Host kernel updates can change performance** without any image rebuild. Before benchmarking, run `vulkaninfo --summary` on the host and record the `driverInfo` line — an empty/mistyped ICD path silently falls back to whatever else is installed (this exact trap bit a B580 tester; see §3 source).
- The container's ICDs are the default. If you mount the host's `/usr/share/vulkan/icd.d`, host drivers win by path order — use `VK_DRIVER_FILES` to force one or the other (see TUNING §4).
- No Level Zero, no ROCm runtime, no IGC in this image. That's a feature: fewer moving parts, smaller image, no "version triangle".

## 3. B70: Mesa 26.1 is the decode lever (not llama.cpp)

**Public evidence:**

- [ggml-org/llama.cpp discussion #27777](https://github.com/ggml-org/llama.cpp/discussions/27777) — on an Arc B580 (same BMG family, 12 GB), swapping **only** the ANV driver Mesa 26.0.8 → 26.1.7 took decode from ~30 → ~67 tok/s (2.05–2.21×) on two unrelated models, with a flat context-scaling curve up to 128k. The kernel made no difference; the gain is entirely userspace ANV.
- [B70 field report (Jonathan Mann, 2026-06/07)](https://jonathanmann.tech/blog/intel-arc-b70-llama-cpp-benchmarks/) — on the actual B70, Mesa 26.1 roughly doubled single-stream Vulkan decode; after that, **Vulkan beat SYCL at every concurrency level tested** (4 and 8 streams) and won single-stream on a MoE model. His correction (2026-07-31): the `matrix cores:` device line is *not* a reliable indicator of the fast path, and q4_0 KV costs ~half generation speed past 16k context on Vulkan — **f16 KV holds up at depth**.

**What this means for this repo:**

1. The Dockerfile's `MESA_VERSION` pin-check exists because Mesa below 26.1 (e.g. the stock Ubuntu 26.04 archive's 26.0.x) would silently halve B70 decode. The base stage therefore pulls `mesa-vulkan-drivers` from the kisak-mesa PPA (`MESA_PPA`) to guarantee the 26.1+ cooperative-matrix2 path; the pin-check fails the build if the installed driver is older. CI tracks Mesa releases and rebuilds when they land.
2. **f16 KV is the default recommendation for B70** (32 GB can afford it at 96k); q8_0 only when adding an MTP draft or pushing to 128k.
3. Do not chase llama.cpp commits expecting decode gains on B70 — re-measure after **Mesa** updates instead.

## 4. 7900 XTX: Vulkan is a first-class, low-friction path

**Public evidence:**

- [1337hero/rx7900xtx-llama-bench-vulcan](https://github.com/1337hero/rx7900xtx-llama-bench-vulcan) — dedicated 7900 XTX Vulkan benchmark repo (multiple models/quants).
- [ROCm vs Vulkan on the RX 7900 XTX (A Guy in Tech)](https://aguyintech.com/rocm-vs-vulkan-on-the-rx-7900-xtx/) — Vulkan competitive with ROCm for token generation; far less setup friction.
- Counterpoint to keep in mind: [ggml issue #20934](https://github.com/ggml-org/llama.cpp/issues/20934) documents *ROCm* regressing below other paths on some RDNA3 workloads — one more reason a vendor-neutral Vulkan image is useful as the fallback.

**What this means for this repo:**

1. 24 GB is the ceiling: Q4_K_M 27B (≈18.9 GB) + KV leaves little headroom. The initial recommendation is **≤32k context with q8_0 KV** for 27B-class, or 8B-class at 64k+. Untested here — first benchmark must establish the real ceiling.
2. RADV updates in Mesa matter for RDNA3 too; the same `MESA_VERSION` pin serves both cards.

## 5. Cooperative matrices: what actually runs on each card

- **Intel (ANV):** the decode lever is the cooperative-matrix matmul path. Mesa ≤26.0 advertised `KHR_coopmat`; 26.1+ advertises the richer `NV_coopmat2`-class path. Note the field report's correction: the *label* in llama.cpp's device line (`matrix cores: …`) is not dependable — trust throughput, not the string.
- **AMD (RADV):** RDNA3 has no cooperative-matrix extension; matmul runs as plain compute shaders. Performance comes from shader scheduling + RADV driver quality. `GGML_VULKAN_INTEGER_DOT` feature tests in the build detect what's available per device at runtime.

## 6. Flash Attention & speculative decoding on Vulkan

- **Flash Attention:** supported and enabled by default with `--flash-attn on`. No known B70/7900XTX regressions in public reports; first benchmark should include a FA on/off pair to confirm.
- **Speculative / MTP:** the paths exist in upstream llama.cpp and are backend-agnostic, but there are **no public B70 or 7900 XTX Vulkan+MTP numbers** we can point at. The SYCL repo's memory math (Q4_0 draft ≈ 2–3 GB, Q8_0 draft ≈ 5.9 GB for Qwen3.8-27B) carries over; the q8_0-KV rule for MTP + large context should be re-verified on Vulkan in the first benchmark round.

## 7. KV cache rules (initial, carried from the SYCL repo — re-verify)

| Card | KV type | When | Why |
|------|---------|------|-----|
| B70 | **f16** | default, ≤96k, no draft | Fastest; 32 GB affords it; f16 holds up at depth on Vulkan (field report §3) |
| B70 | q8_0 | MTP draft + ≥96k, or 128k | Halves KV so the draft fits without host-RAM OOM |
| 7900 XTX | f16 | ≤16k, no draft | Fastest while it fits |
| 7900 XTX | **q8_0** | ≥32k or any draft | 24 GB ceiling; q4_0 KV is explicitly discouraged past 16k (field report correction) |

## 8. Known pitfalls (carried over + Vulkan-specific)

1. **Silent partial offload.** SIGKILL on the server orphans children that keep holding VRAM; the next instance sees less free memory and silently offloads fewer layers *with no error anywhere*. Always read the `n_gpu_layers` line in the log before trusting a number (the B580 tester's 13.5 tok/s "result" was exactly this).
2. **ICD fallback trap.** A mistyped `VK_DRIVER_FILES` path falls back to the system driver silently — verify `vulkaninfo --summary | grep driverInfo` shows the expected driver before benchmarking.
3. **Host driver drift.** Because the host kernel + (optionally) host ICDs participate, two runs of the *same image* on different hosts can differ. Record host state in every benchmark report.
4. **Batched `eval time` is not user throughput** — same rule as the SYCL repo; use streamed `tg` or single-shot timings.

## 9. Source list

- [ggml-org/llama.cpp discussion #27777 — Mesa 26.1.7 doubles Vulkan throughput on Arc B580](https://github.com/ggml-org/llama.cpp/discussions/27777)
- [Don't trust your old benchmarks: a weekend of testing on the Intel Arc B70](https://jonathanmann.tech/blog/intel-arc-b70-llama-cpp-benchmarks/) (incl. 2026-07-31 correction)
- [PMZFX/intel-arc-pro-b70-benchmarks](https://github.com/PMZFX/intel-arc-pro-b70-benchmarks) (pre-Mesa-26.1 data; SYCL-favorable, now dated)
- [Phoronix — llama.cpp Vulkan end-of-2025 review (B580 vs RTX 50 vs RX 9000)](https://www.phoronix.com/review/llama-cpp-vulkan-eoy2025)
- [1337hero/rx7900xtx-llama-bench-vulcan](https://github.com/1337hero/rx7900xtx-llama-bench-vulcan)
- [ROCm vs Vulkan on the RX 7900 XTX — A Guy in Tech](https://aguyintech.com/rocm-vs-vulkan-on-the-rx-7900-xtx/)
- [Is the RX 7900 XTX Worth It for Local AI in 2026? ROCm vs Vulkan](https://aliteq.com/rx-7900-xtx-worth-it-local-ai-rocm-vs-vulkan-2026)
- [ggml-org/llama.cpp issue #20934 — ROCm token-gen regression on RDNA3](https://github.com/ggml-org/llama.cpp/issues/20934)
- Upstream: [`ggml/src/ggml-vulkan`](https://github.com/ggml-org/llama.cpp/tree/master/ggml/src/ggml-vulkan), [`.devops/vulkan.Dockerfile`](https://github.com/ggml-org/llama.cpp/blob/master/.devops/vulkan.Dockerfile)
- Sibling repo (SYCL/B70, methodology + memory math): [snailium/llama.cpp-sycl-intel-b70](https://github.com/snailium/llama.cpp-sycl-intel-b70)
