#!/usr/bin/env bash
set -euo pipefail

# Build community Vulkan-optimized llama.cpp image (dual-target: B70 + 7900 XTX)
# Usage:
#   ./scripts/build-vulkan-image.sh [target] [tag] [mesa_version]
# target: server (default), light, full
# mesa_version: reference pin; build FAILS if distro mesa-vulkan-drivers is older

TARGET=${1:-server}
TAG=${2:-llama.cpp-vulkan:${TARGET}}
MESA=${3:-26.1.7}

echo "Building target=${TARGET} tag=${TAG} (Mesa reference pin: ${MESA})"

docker build \
  --target "${TARGET}" \
  -t "${TAG}" \
  -f .devops/vulkan.Dockerfile \
  --build-arg UBUNTU_VERSION=26.04 \
  --build-arg MESA_VERSION="${MESA}" \
  .

echo "Done: ${TAG}"
echo "Test with:"
echo "  docker run --rm -it --device /dev/dri -v \$PWD/models:/models -p 8080:8080 ${TAG} --help"
echo "Remember: check 'n_gpu_layers' in the server log before trusting any benchmark."
