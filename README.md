# llama.cpp + Vulkan for Intel Arc B70 & AMD RX 7900 XTX (Community)

A maintained, up-to-date Docker image + guidance for running **llama.cpp with the Vulkan backend** on two very different cards from a **single image**:

- **Intel Arc Pro B70** (32 GB, BMG-G31 / Xe2, Battlemage)
- **AMD Radeon RX 7900 XTX** (24 GB, RDNA3)

The official `ghcr.io/ggml-org/llama.cpp:vulkan-*` images are generic and lag on the Mesa driver stack. This community effort keeps the **Mesa ANV/RADV** drivers current — which is where the real performance lives for both cards — while **keeping every feature enabled**: Flash Attention, speculative decoding / MTP, reorder kernels, and dynamic backends.

## ✨ Highlights

- **One image, two cards.** The Vulkan backend is the common denominator: no ROCm pinning games on AMD, no oneAPI/IGC triangle on Intel. Same binary, same flags, different `--device` index.
- **B70 decode doubled by Mesa, not by llama.cpp.** Mesa 26.1+ ANV exposes the cooperative-matrix extension path on Battlemage; on the B580 (same family) that took Ollama/llama.cpp decode from ~30 → ~67 tok/s ([ggml-org discussion #27777](https://github.com/ggml-org/llama.cpp/discussions/27777)). On the B70, post-Mesa-26.1 Vulkan now **matches or beats SYCL at concurrency** and wins single-stream decode on MoE models ([field report](https://jonathanmann.tech/blog/intel-arc-b70-llama-cpp-benchmarks/)). The image pins-checks the distro Mesa version at build time so a regressed archive fails loudly instead of silently halving throughput.
- **7900 XTX: Vulkan is a first-class path.** Community benchmarks consistently show llama.cpp-Vulkan competitive with (and in some workloads ahead of) ROCm on RDNA3, with far less setup friction ([1337hero's 7900XTX Vulkan bench repo](https://github.com/1337hero/rx7900xtx-llama-bench-vulcan), [ROCm-vs-Vulkan comparison](https://aguyintech.com/rocm-vs-vulkan-on-the-rx-7900-xtx/)).

> **Status: early.** This repo is a fresh fork of the community-maintenance pattern from [`snailium/llama.cpp-sycl-intel-b70`](https://github.com/snailium/llama.cpp-sycl-intel-b70). The image builds; **benchmarks on real B70 / 7900 XTX hardware are still to be collected** — see `STATUS.md` and `benchmark/` for what is verified vs. expected.

## Why a community Vulkan image?

- The Vulkan backend's performance is **driver-bound**: Mesa ANV/RADV version matters more than the llama.cpp commit for both cards.
- Distro archives regress: an Ubuntu point-release or a PPA-less archive can ship a Mesa older than the cooperative-matrix fix, silently halving B70 decode. CI + build-time pin-check guard against that.
- Dual-card serving needs one image with **both** ANV and RADV in it (the distro `mesa-vulkan-drivers` package provides both — we just verify versions).
- Flash-Attn and MTP/speculative decoding must stay **on** — we never disable them.

## Quick start (Docker)

### 1. Build the image

From the repo root (contains `.devops/vulkan.Dockerfile`):

```bash
# Convenience script
./scripts/build-vulkan-image.sh server

# ...or directly (Mesa 26.1+ comes from the kisak-mesa PPA by default)
docker build \
  --target server \
  -t llama.cpp-vulkan:server \
  -f .devops/vulkan.Dockerfile \
  --build-arg UBUNTU_VERSION=26.04 \
  --build-arg MESA_PPA=kisak/kisak-mesa \
  --build-arg MESA_VERSION=26.1 \
  .
```

Build targets: `server` (recommended), `light`, `full`. The runtime Vulkan driver (`mesa-vulkan-drivers`) is pulled from the **kisak-mesa PPA** so the image carries Mesa 26.1+ — the ANV cooperative-matrix2 decode lever on B70. `MESA_PPA=none` builds against the Ubuntu archive only (26.0.x — slower B70 decode). `MESA_VERSION` is a **major.minor** reference pin: the base stage **fails the build** if the installed `mesa-vulkan-drivers` is older than it; point releases (e.g. 26.2.2) never gate. CI detects the current PPA version from Launchpad's apt index and rebuilds when the major.minor moves.

> **Driver model:** unlike the SYCL image (which ships its own IGC/compute-runtime), this image relies on the **host kernel driver** (`xe` for Intel, `amdgpu` for AMD) and ships the **user-space Vulkan ICDs** (ANV + RADV via `mesa-vulkan-drivers`). That is the standard, lowest-friction Vulkan deployment: host kernel does the DMA, container's ICD does the compute.

### 2. Run on B70 or 7900 XTX

Find your render device first:

```bash
ls -l /dev/dri          # typically /dev/dri/renderD128 (Intel) or renderD129 (AMD dGPU)
vulkaninfo --summary    # host check: expect "Intel(R) Arc(TM) Pro B70" and/or "Radeon RX 7900 XTX"
```

Docker run — **B70** (pick the Intel device index; with only one GPU it is `0`):

```bash
docker run --rm -it \
  --device /dev/dri \
  -v /path/to/models:/models \
  -p 8080:8080 \
  llama.cpp-vulkan:server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --device 0 \
  --n-gpu-layers 999 \
  --flash-attn on \
  --ctx-size 98304 \
  --cache-type-k f16 --cache-type-v f16 \
  --port 8080 --host 0.0.0.0
```

Docker run — **7900 XTX** (same image; on a dual-GPU box pick the AMD index, e.g. `1`):

```bash
docker run --rm -it \
  --device /dev/dri \
  -v /path/to/models:/models \
  -p 8080:8080 \
  llama.cpp-vulkan:server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf \
  --device 1 \
  --n-gpu-layers 999 \
  --flash-attn on \
  --ctx-size 65536 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --port 8080 --host 0.0.0.0
```

**Runtime environment (Vulkan):**

```bash
# Optional: force a specific ICD (e.g. when host has multiple Vulkan drivers)
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json     # B70 only
# or
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json   # 7900 XTX only

# Optional: disable cooperative-matrix path (debugging only — do NOT ship this)
# GGML_VK_DISABLE_COOPMAT2=1
```

A `docker-compose.yml` and ready-made launchers for both cards are included (`examples/b70-server.sh`, `examples/7900xtx-server.sh`).

### Recommended configuration (initial — to be validated on hardware)

| Card | Context | KV | Notes |
|------|---------|----|-------|
| **B70 32 GB** | 96k | **f16** | Full offload; f16 KV holds up at depth on the Vulkan path (per B70 field report) |
| **B70 32 GB + MTP draft** | 96k–128k | **q8_0** | Halves KV so a ~5.9 GB draft fits without host-RAM OOM (SYCL-repo rule of thumb; re-verify on Vulkan) |
| **7900 XTX 24 GB** | 32k–64k | **q8_0** for ≥32k, f16 below | 24 GB is the constraint: Q4_K_M 27B ≈ 18.9 GB leaves little headroom — prefer 8B-class at 64k+ or 27B at ≤32k |

- `--n-gpu-layers 999` (offload everything) on both cards.
- `--flash-attn on` (Vulkan backend supports it).
- **Always verify the offload line in the server log** (`llama_model_loader: ... n_gpu_layers=...`) — a silent partial offload is the classic misread-benchmark trap (see `docs/VULKAN-TUNING.md` §5).

## Project structure

```
.
├── README.md                   ← you are here
├── STATUS.md                   ← current pins & verified-vs-expected state
├── CONTRIBUTING.md             ← how to contribute (benchmarks welcome)
├── docs/
│   ├── VULKAN-KNOWLEDGE.md    ← all field knowledge & the "why" behind the config
│   └── VULKAN-TUNING.md       ← hands-on flags, pitfalls, per-card notes
├── benchmark/
│   ├── METHODOLOGY.md          ← the 5-task test suite + metric definitions (mirrors SYCL repo)
│   ├── configs/                ← one file per reproducible server config
│   ├── results/                ← one file per dated test run (empty until first hardware run)
│   └── incidents/              ← stability incident logs
├── examples/
│   ├── b70-server.sh           ← recommended launcher for Arc Pro B70
│   └── 7900xtx-server.sh       ← recommended launcher for RX 7900 XTX
├── scripts/
│   ├── build-vulkan-image.sh   ← convenience build script
│   └── promote-vulkan-image.sh ← promote a tested candidate digest to :stable / semver
├── .devops/vulkan.Dockerfile   ← the build pipeline (all version pins)
├── docker-compose.yml
├── .github/workflows/          ← CI auto-build (stable / dev + upstream tracking)
└── llama.cpp/                  ← upstream llama.cpp vendored via git subtree
```

## What we keep enabled (by design)

- **Flash Attention** (Vulkan support is mature).
- **Speculative decoding / MTP** paths.
- Reorder / optimized `mul_mat` kernels for Q4_K etc.
- **Dynamic backends** (`GGML_BACKEND_DL`).
- F16 KV where VRAM allows (q8_0 for large context + draft).
- Full CPU-variant fallbacks.

We explicitly do **not** set `GGML_VULKAN_DEBUG`, `GGML_VULKAN_CHECK_RESULTS`, or any `DISABLE_*` flag in the shipped image.

## Benchmarks

`benchmark/` holds the test methodology (mirrored from the SYCL repo so results are comparable across backends) and will collect measured runs. **Start with [`benchmark/METHODOLOGY.md`](./benchmark/METHODOLOGY.md)** for the 5-task suite and metric conventions.

> **Testing methodology matters.** Always verify cards with a real `/v1/chat/completions` → `finish_reason=stop`, keep thinking **off** for artifact tasks, check the offload line, and never trust llama.cpp's batched `eval time` figures as the real throughput (see methodology).

## Building from source (bare metal, for comparison)

```bash
sudo apt install -y build-essential cmake ninja-build git libssl-dev \
    libvulkan-dev glslc spirv-headers mesa-vulkan-drivers
cmake -S llama.cpp -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=OFF \
  -DGGML_VULKAN=ON \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DLLAMA_BUILD_TESTS=OFF
cmake --build build --config Release -j$(nproc)
```

Then run with `--device <index>` as above. The prebuilt container is the recommended path — it pins the Mesa version that matters for B70 decode.

## Performance notes (expected, to be confirmed on hardware)

- **B70:** post-Mesa-26.1 Vulkan is competitive with SYCL and wins at concurrency (8-stream aggregate ≈ 8× single-shot in the field report). Single-stream dense prefill may still trail SYCL+oneDNN/XMX — recheck on each Mesa/llama.cpp update.
- **7900 XTX:** expect parity-with-ROCm token generation and much simpler ops; RDNA3's 24 GB is the ceiling for 27B-class at large context.
- **Both:** cooperative-matrix matmul path is the decode lever on Intel; on AMD it's plain compute-shader throughput — driver version still matters (RADV updates in Mesa).

See `benchmark/` for measured numbers as they land.

## CI / Automatic builds

Two dedicated workflows keep pins fresh without manual work (mirroring the SYCL repo's pattern):

| Workflow | Branch | Schedule | What it tracks |
|----------|--------|----------|----------------|
| `build-stable.yml` | `main` | Every 4 hours | llama.cpp `v*` tags + **Mesa** release (ANV/RADV) |
| `build-dev.yml` | `dev` | Saturdays 00:00 UTC | llama.cpp + latest Mesa (skips when the newest tag is a release, else builds latest `b*`) |

When a change is detected, CI builds a **temporary tag** (`server-m<Mesa>-<llama>-YYYYMMDD-HHMM` / `server-dev-…`) and opens a GitHub Issue with diffs. The maintainer then pulls it to real B70 / 7900 XTX hardware, tests, and only then creates a proper named tag via `scripts/promote-vulkan-image.sh`.

## Contributing

Contributions that keep both cards current and high-performance are very welcome — see [`CONTRIBUTING.md`](./CONTRIBUTING.md). Especially valuable: **verified benchmarks on real B70 or 7900 XTX hardware** (this repo's biggest gap right now), Mesa pin updates, and dual-card incident reports.

## License & credits

- License: same as upstream — MIT for the project structure and docs here.
- Upstream: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) (Vulkan backend: `ggml/src/ggml-vulkan`)
- Mesa ANV/RADV driver teams; Intel `xe` / AMD `amdgpu` kernel driver teams.
- Community testers who shared B70 + Vulkan and 7900 XTX + Vulkan recipes (see `docs/VULKAN-KNOWLEDGE.md` §9 for the source list).

---

**This is a community effort.** Use at your own risk. Test thoroughly with your workloads and report issues so the pins stay fresh for B70 and 7900 XTX.
