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
# Ubuntu 26.04's archive ships mesa-vulkan-drivers 26.0.x, which does NOT expose
# VK_NV_cooperative_matrix2 on Battlemage (the ~2x B70 decode lever; it needs
# Mesa 26.1+). We therefore pull the runtime driver from the kisak-mesa "fresh"
# PPA inside the base stage, which tracks the latest Mesa point release for the
# Ubuntu series. MESA_VERSION is a *major.minor reference pin*: the base stage
# fails the build if the installed mesa-vulkan-drivers is older than it (point
# releases never gate). Override the PPA (e.g. to a mirror, or disable it for
# an offline/archive-only base by passing MESA_PPA=none) via --build-arg.
ARG MESA_PPA=kisak/kisak-mesa
ARG MESA_VERSION=26.1
# Vulkan SDK version used to extract glslc (shader AOT compiler) — see build stage.
# libvulkan-dev / spirv-headers come from the distro archive, not the SDK.
ARG VULKAN_SDK_VERSION=1.4.357.1

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

# Global ARGs used inside a stage's RUN must be re-declared here; otherwise the
# shell sees them as empty (Docker stage scoping). GGML_VULKAN below drives the
# cmake -DGGML_VULKAN flag for the compile step - an empty value disables the
# Vulkan backend silently (builds CPU-only). Keep this ARG line in sync.
ARG GGML_VULKAN

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git build-essential cmake ninja-build wget xz-utils ca-certificates curl \
      libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# glslc (shader AOT) ships only in the Vulkan SDK. We commit the single binary
# extracted from the official SDK tarball at .devops/bin/glslc (see its SHA256
# note below) so builds work even when the SDK CDN blocks container egress —
# some CDNs serve an HTML challenge page to datacenter IPs, which broke in-image
# downloads. If the committed binary is missing, fall back to fetching it from
# the official LunarG download endpoint. Everything else build-time
# (libvulkan-dev, spirv-headers) comes from the distro archive so it matches
# the runtime loader.
COPY .devops/bin/glslc /usr/local/bin/glslc
RUN chmod 755 /usr/local/bin/glslc && \
    if ! glslc --version >/dev/null 2>&1; then \
      echo "committed glslc unusable — falling back to official SDK download" && \
      curl -sL "https://sdk.lunarg.com/sdk/download/${VULKAN_SDK_VERSION}/linux/vulkan_sdk.tar.xz?Human=true" -o /tmp/vsdk.tar.xz && \
      tar -xJf /tmp/vsdk.tar.xz -C /tmp --wildcards '*/bin/glslc' && \
      install -m 755 /tmp/*/*/bin/glslc /usr/local/bin/glslc && \
      rm -rf /tmp/vsdk.tar.xz /tmp/1.*; \
    fi && glslc --version

# Build-time only Vulkan headers (libvulkan-dev, spirv-headers).
RUN apt-get update && \
    apt-get install -y --no-install-recommends libvulkan-dev spirv-headers && \
    rm -rf /var/lib/apt/lists/*

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

# Stage every runtime/shared library into /app/lib. libggml.so + libggml-base.so
# (core) and the per-backend MODULE libs (libggml-vulkan.so, libggml-cpu-*.so ...)
# are all written by ninja under build/bin; search the whole tree in case a layout
# differs. Assert the Vulkan backend landed - a silent CPU-only build is the failure
# mode we most want to catch here (see the GGML_VULKAN ARG note in this file).
RUN mkdir -p /app/lib && \
    find build -name "*.so*" -exec cp -P {} /app/lib \; && \
    test -n "$(ls /app/lib/libggml-vulkan.so* 2>/dev/null)" && \
      echo "OK: Vulkan backend staged ($(ls /app/lib/libggml-vulkan.so* | tr '\n' ' '))" \
    || { echo "FATAL: libggml-vulkan.so missing - was -DGGML_VULKAN actually ON?" >&2; exit 1; }

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
ARG MESA_PPA
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
#   - mesa-vulkan-drivers: ANV (Intel) + RADV (AMD) - the critical package.
#   - libglvnd/GL stack: some ICDs resolve GL entry points through it.
# When MESA_PPA is set (default), enable it first so apt resolves mesa-vulkan-drivers
# to >= 26.1 (the ANV cooperative-matrix2 decode lever on Battlemage) rather than the
# 26.0.x the Ubuntu 26.04 archive carries. software-properties-common provides
# add-apt-repository; apt resolves the PPA's higher mesa/libdrm automatically.
# The install below is deliberately before any version pin so the PPA's co-dependent
# libdrm/llvm stack stays consistent; the separate pin-check RUN enforces MESA_VERSION.
RUN set -eux; \
    apt-get update; \
    if [ -n "${MESA_PPA}" ] && [ "${MESA_PPA}" != "none" ]; then \
      apt-get install -y --no-install-recommends ca-certificates software-properties-common; \
      add-apt-repository -y --no-update "ppa:${MESA_PPA}"; \
      apt-get update; \
    fi; \
    apt-get install -y --no-install-recommends \
      libgomp1 curl ffmpeg \
      libvulkan1 mesa-vulkan-drivers \
      libglvnd0 libgl1 libglx0 libegl1 libgles2; \
    echo "Selected mesa-vulkan-drivers: $(apt-cache policy mesa-vulkan-drivers | awk '/Candidate:/{print $2; exit}')";

# Pin-check: fail the build if mesa-vulkan-drivers is older than the reference pin
# MESA_VERSION. A regressed driver (pre-26.1) would silently halve B70 decode, so we
# surface that as a hard error instead of shipping a nominally-Vulkan image that lacks
# the fast cooperative-matrix2 path. Pass MESA_PPA=none only with an archive/base that
# already carries Mesa >= MESA_VERSION - this check then gates it.
# MESA_VERSION is a major.minor reference pin (e.g. 26.1). The installed version is
# trimmed to major.minor before comparison, so point releases (26.2.2) never gate the
# build - only a driver older than the pin does. A 3-part value is accepted and trimmed.
RUN set -e; \
    INSTALLED=$(dpkg-query -W -f='${Version}' mesa-vulkan-drivers | cut -d. -f1-2); \
    echo "mesa-vulkan-drivers installed: $INSTALLED (reference pin: $MESA_VERSION)"; \
    REF=$(echo "$MESA_VERSION" | cut -d. -f1-2); \
    MAJ_REF=${REF%%.*}; MIN_REF=${REF#*.}; \
    MAJ_INST=${INSTALLED%%.*}; MIN_INST=${INSTALLED#*.}; \
    if [ "$MAJ_INST" -lt "$MAJ_REF" ] || { [ "$MAJ_INST" -eq "$MAJ_REF" ] && [ "$MIN_INST" -lt "$MIN_REF" ]; }; then \
      echo "ERR: installed Mesa $INSTALLED < reference $REF - B70 cooperative-matrix2 path is not present." >&2; \
      echo "     Rebuild with the kisak-mesa PPA enabled (default) or a base carrying Mesa >= $REF." >&2; \
      exit 1; \
    fi

# Trim build/PPA-enable tooling out of the image. Mesa/libvulkan stay; the
# add-apt-repository helper stack (software-properties-common + Python) is no
# longer needed at runtime and autoremove drops it (and its orphans) for us.
RUN apt-get purge -y --auto-remove software-properties-common python3-apt 2>/dev/null || true; \
    apt-get autoremove -y && apt-get clean -y && \
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
