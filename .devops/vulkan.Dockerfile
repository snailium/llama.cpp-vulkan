# Community-maintained Vulkan Docker for llama.cpp
# Dual-target: Intel Arc Pro B70 (Battlemage / BMG-G31, Xe2) + AMD Radeon RX 7900 XTX (RDNA3)
# Goal: a single image that serves both cards via the Vulkan backend, with the
#       current Mesa ANV/RADV drivers baked in. All features enabled:
#       Flash Attention, speculative decoding / MTP, reorder kernels, dynamic backends.
# Do NOT disable optimizations (no GGML_VULKAN_DEBUG / CHECK_RESULTS / DISABLE_* flags).
#
# Why Vulkan for both cards?
#   - Intel B70: Mesa 26.1+ ANV exposes the cooperative-matrix path (NV_coopmat2),
#     which roughly doubled decode throughput vs 26.0.x on Battlemage and now
#     matches or beats SYCL at concurrency (see docs/VULKAN-KNOWLEDGE.md §3).
#   - AMD 7900 XTX: the Vulkan backend is a first-class, low-friction path — no
#     ROCm pinning games, works with any recent amdgpu kernel driver.
#   - One image, one API surface for both cards = simpler ops + cross-card benchmarks.

ARG UBUNTU_VERSION=26.04
ARG BUILD_DATE=N/A
ARG APP_VERSION=N/A
ARG APP_REVISION=N/A

# === Mesa / Vulkan driver stack (passed from CI via --build-arg) ===
# Defaults track the latest Mesa stable with the ANV cooperative-matrix fix.
# MESA_VERSION is used only as a *reference pin* recorded in the image labels;
# on Ubuntu 26.04 we install `mesa-vulkan-drivers` from the distro archive so
# that the driver matches the distro's libvulkan/GL stack (CI verifies the
# installed version against MESA_VERSION and fails loudly if it regresses below).
ARG MESA_VERSION=26.1.7
# Vulkan SDK components needed at build time (glslc + headers for shader AOT)
ARG VULKAN_SDK_COMPONENTS="libvulkan-dev glslc spirv-headers"

# Feature toggles — KEEP ENABLED for best perf on B70 / 7900 XTX
ARG GGML_VULKAN=ON
# Optional: build the Web UI (default OFF, server-only image)
ARG NODE_VERSION=24
ARG BUILD_WEBUI=0

# === Build Image (web UI) ===
FROM docker.io/node:$NODE_VERSION AS web

ARG APP_VERSION
ARG BUILD_WEBUI

WORKDIR /app/tools/ui

# Make web UI optional. In this community repo the source lives under llama.cpp/tools/ui;
# create a stub dist when not building the UI so the build stage always has something to copy.
RUN mkdir -p dist && \
    if [ "$BUILD_WEBUI" = "1" ]; then \
      for src in /tmp/src/tools/ui /context/tools/ui tools/ui llama.cpp/tools/ui; do \
        if [ -f "$src/package.json" ]; then \
          echo "Found web UI source at $src"; \
          cp "$src"/package*.json ./ 2>/dev/null || true; \
          cp -r "$src"/* ./ 2>/dev/null || true; \
          npm ci --prefer-offline || true; \
          LLAMA_BUILD_NUMBER="$APP_VERSION" npm run build || true; \
          break; \
        fi; \
      done; \
    fi && \
    if [ ! -f dist/index.html ]; then \
      echo '<!doctype html><html><head><meta charset="utf-8"><title>llama.cpp</title></head><body><h1>Web UI not built</h1><p>This image was built with BUILD_WEBUI=0 (server-only). Rebuild with --build-arg BUILD_WEBUI=1 if you have the tools/ui sources.</p></body></html>' > dist/index.html; \
    fi

# === Build stage ===
FROM docker.io/ubuntu:$UBUNTU_VERSION AS build

ARG VULKAN_SDK_COMPONENTS

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git build-essential cmake ninja-build wget xz-utils ca-certificates curl \
      libssl-dev \
      ${VULKAN_SDK_COMPONENTS} \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

RUN mkdir -p tools/ui/dist
COPY --from=web /app/tools/ui/dist/ tools/ui/dist/

# Build with Vulkan + dynamic backends + all CPU variants.
# No GGML_VULKAN_DEBUG / CHECK_RESULTS — those are dev-only and slow the hot path.
# Shader AOT (glslc) is done at build time by ggml's shader pipeline; runtime JIT
# of compute shaders still happens per-device on first use (cached in ~/.cache/llama.cpp).
RUN echo "Building llama.cpp with Vulkan backend (dual-target: B70 + 7900 XTX)" && \
    cmake -S llama.cpp -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_NATIVE=OFF \
      -DGGML_VULKAN=${GGML_VULKAN} \
      -DGGML_BACKEND_DL=ON \
      -DGGML_CPU_ALL_VARIANTS=ON \
      -DLLAMA_BUILD_TESTS=OFF && \
    cmake --build build --config Release -j$(nproc)

RUN mkdir -p /app/lib && \
    find build -name "*.so*" -exec cp -P {} /app/lib \;

# Best-effort packaging of optional Python helper tools (conversion scripts, gguf-py,
# requirements). llama.cpp's layout varies by version, so each copy is intentionally
# tolerant of a missing source (|| true) — the server binary itself is the required
# artifact, these are conveniences.
RUN mkdir -p /app/full \
    && cp build/bin/* /app/full \
    && cp llama.cpp/*.py /app/full 2>/dev/null || true \
    && { [ -d llama.cpp/conversion ] && cp -r llama.cpp/conversion /app/full; } || true \
    && { [ -d llama.cpp/gguf-py ] && cp -r llama.cpp/gguf-py /app/full; } || true \
    && { [ -d llama.cpp/requirements ] && cp -r llama.cpp/requirements /app/full; } || true \
    && { [ -f llama.cpp/requirements.txt ] && cp llama.cpp/requirements.txt /app/full; } || true \
    && { [ -f llama.cpp/.devops/tools.sh ] && cp llama.cpp/.devops/tools.sh /app/full/tools.sh; } || true

# === Base image (runtime driver stack) ===
FROM docker.io/ubuntu:$UBUNTU_VERSION AS base

ARG BUILD_DATE=N/A
ARG APP_VERSION=N/A
ARG APP_REVISION=N/A
ARG MESA_VERSION
ARG IMAGE_URL=https://github.com/ggml-org/llama.cpp
ARG IMAGE_SOURCE=https://github.com/ggml-org/llama.cpp
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.revision=$APP_REVISION \
      org.opencontainers.image.title="llama.cpp (community Vulkan for Intel Arc B70 + AMD RX 7900 XTX)" \
      org.opencontainers.image.description="LLM inference in C/C++ — Vulkan backend, dual-target: Battlemage B70 + RDNA3 7900 XTX" \
      org.opencontainers.image.url=$IMAGE_URL \
      org.opencontainers.image.source=$IMAGE_SOURCE \
      org.opencontainers.image.mesa.reference=$MESA_VERSION

# Install the user-space Vulkan driver stack.
#   - libvulkan1: loader (matches distro)
#   - mesa-vulkan-drivers: ANV (Intel) + RADV (AMD) — this is the critical package.
#     On Ubuntu 26.04 it ships Mesa >= 26.1.x, which exposes VK_NV_cooperative_matrix2
#     on Battlemage (the ~2x decode lever). We pin-check below.
#   - libglvnd/GL stack: needed by some ICDs to resolve GL entry points.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libgomp1 curl ffmpeg \
      libvulkan1 mesa-vulkan-drivers \
      libglvnd0 libgl1 libglx0 libegl1 libgles2 \
    && rm -rf /var/lib/apt/lists/*

# Pin-check: fail the build if the distro's Mesa regressed below the reference pin.
# (CI passes MESA_VERSION from the tracked Mesa release; a distro archive that is
#  older than the cooperative-matrix fix would silently halve B70 decode.)
RUN set -e; \
    INSTALLED=$(dpkg-query -W -f='${Version}' mesa-vulkan-drivers | cut -d. -f1-2); \
    echo "mesa-vulkan-drivers installed: $INSTALLED (reference pin: $MESA_VERSION)"; \
    MAJ_REF=${MESA_VERSION%%.*}; MIN_REF=$(echo "$MESA_VERSION" | cut -d. -f2); \
    MAJ_INST=${INSTALLED%%.*}; MIN_INST=$(echo "$INSTALLED" | cut -d. -f2); \
    if [ "$MAJ_INST" -lt "$MAJ_REF" ] || { [ "$MAJ_INST" -eq "$MAJ_REF" ] && [ "$MIN_INST" -lt "$MIN_REF" ]; }; then \
      echo "ERR: distro Mesa $INSTALLED < reference $MESA_VERSION — B70 cooperative-matrix path may be missing." >&2; \
      exit 1; \
    fi

RUN apt-get autoremove -y && apt-get clean -y && \
    rm -rf /tmp/* /var/tmp/* && \
    find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete && \
    find /var/cache -type f -delete

# === Full (conversion + server + cli) ===
FROM base AS full

COPY --from=build /app/lib/ /app
COPY --from=build /app/full /app

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git python3 python3-pip python3-venv && \
    python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --upgrade pip setuptools wheel && \
    { [ -f requirements.txt ] && pip install -r requirements.txt; } || true && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /tmp/* /var/tmp/* && \
    find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete && \
    find /var/cache -type f -delete

ENV PATH="/opt/venv/bin:$PATH"

ENTRYPOINT ["/app/tools.sh"]

# === Light (cli only) ===
FROM base AS light

COPY --from=build /app/lib/ /app
COPY --from=build /app/full/llama /app/full/llama-cli /app/full/llama-completion /app/

WORKDIR /app

ENTRYPOINT [ "/app/llama-cli" ]

# === Server (recommended for B70 + 7900 XTX) ===
FROM base AS server

ENV LLAMA_ARG_HOST=0.0.0.0

COPY --from=build /app/lib/ /app
COPY --from=build /app/full/llama /app/full/llama-server /app/

WORKDIR /app

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
