# Contributing to llama.cpp + Vulkan for Intel Arc B70 & AMD RX 7900 XTX

We welcome contributions that keep **both** cards current and high-performance while **keeping all features enabled**.

## What we value (in priority order)

1. **Verified benchmarks on real hardware** — this repo's biggest gap. Use `benchmark/METHODOLOGY.md` (the 5-task suite, mirrored from the SYCL repo so numbers are comparable across backends) and add reports under `benchmark/results/`. B70 *and* 7900 XTX runs both count; a cross-card comparison is gold.
2. Updated **Mesa reference pin** in `.devops/vulkan.Dockerfile` when ANV/RADV ship perf-relevant fixes, with the before/after numbers to justify it.
3. Fixes or docs that do **not** require disabling Flash Attention, speculative decoding, or setting `GGML_VULKAN_DEBUG` / `CHECK_RESULTS` in the shipped image.
4. Reproduction steps that include:
   - `vulkaninfo --summary` output (driverInfo line!)
   - `uname -a` + host kernel driver (`xe` / `amdgpu`) version
   - Container image digest (`docker buildx imagetools inspect …`)
   - The server log's **offload line** (`n_gpu_layers=…`)
   - Full command line + model quant

## How to propose a change

1. Fork or clone this repo.
2. Update `.devops/vulkan.Dockerfile` (or docs) with new versions + rationale.
3. **Test on real B70 / 7900 XTX if possible** (highly recommended for any Mesa bump).
4. Open a PR with:
   - A summary of the change.
   - Benchmark numbers (pp / tg for a 27B-class model, and an agent-suite run if relevant).
   - Verification that Flash Attention and MTP paths still work.

**Note on CI:** the repository uses two workflows (`build-stable.yml` on `main`, `build-dev.yml` on `dev`) that auto-detect updates to llama.cpp and Mesa. They build a temporary tag and open a GitHub Issue with diffs; the maintainer tests on real hardware before promoting via `scripts/promote-vulkan-image.sh`. You generally do **not** need to trigger builds manually for pin updates — but PRs with local benchmark results are always welcome.

## Scope

This repo focuses on the Docker image, the Mesa/driver stack, and per-card tuning. For changes to the core Vulkan backend (`ggml/src/ggml-vulkan`), contribute directly to [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — the improvement is picked up on the next rebuild.

Thanks for helping keep B70 and 7900 XTX usable for the latest 27B+ models!
