#!/usr/bin/env bash
set -euo pipefail

# Build community Vulkan-optimized llama.cpp image (dual-target: B70 + 7900 XTX)
# Usage:
#   ./scripts/build-vulkan-image.sh [target] [tag]
# target: server (default), light, full
#
# Mesa drivers come from the kisak-mesa PPA inside the Dockerfile base stage so the
# image always carries the Mesa 26.1+ ANV cooperative-matrix2 path B70 needs (~2x
# decode). The Dockerfile MESA_VERSION pin (major.minor) guards that: the build
# fails if the installed driver is older, point releases never gate. Override with
# env vars like:  MESA_VERSION=26.1 ./scripts/build-vulkan-image.sh server

TARGET=${1:-server}
TAG=${2:-llama.cpp-vulkan:${TARGET}}

echo "Building target=${TARGET} tag=${TAG}"
echo "  MESA_PPA=${MESA_PPA:-kisak/kisak-mesa}  MESA_VERSION=${MESA_VERSION:-26.1}"

docker build \
  --target "${TARGET}" \
  -t "${TAG}" \
  -f .devops/vulkan.Dockerfile \
  --build-arg UBUNTU_VERSION=26.04 \
  --build-arg MESA_PPA="${MESA_PPA:-kisak/kisak-mesa}" \
  --build-arg MESA_VERSION="${MESA_VERSION:-26.1}" \
  .

echo "Done: ${TAG}"
echo "Test with:"
echo "  docker run --rm -it --device /dev/dri -v \$PWD/models:/models -p 8080:8080 ${TAG} --help"
echo "Confirm the loaded Mesa is >= 26.1 (view llm_load_tensors / vulkan device line) before benchmarking."
