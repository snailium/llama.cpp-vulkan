#!/usr/bin/env bash
# XTX target for dev candidate server-dev-m26.2-b12020-20261031-1054.
# Config source: llama.cpp-vulkan/docs/GOLDEN-CONFIG.md §4 "7900 XTX - verified
# production config" (read 2026-10-31). No flags are passed; env-var form only.
set -euo pipefail

IMG=ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-dev-m26.2-b12020-20261031-1054
NAME=xtx-vk-b12020-test
CACHE=xtx-vk-b12020-cache

docker rm -f "$NAME" 2>/dev/null || true
docker volume create "$CACHE" >/dev/null

docker run -d --name "$NAME" \
  --device /dev/dri \
  -v /models/qwen3.8-27b:/models:ro \
  -v "$CACHE":/root/.cache \
  -p 18092:8080 \
  --restart no \
  -e VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json \
  -e LLAMA_ARG_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf \
  -e LLAMA_ARG_MMPROJ=/models/mmproj-Qwen3.8-27B-Q8_0.gguf \
  -e LLAMA_ARG_IMAGE_MIN_TOKENS=1024 \
  -e LLAMA_ARG_DEVICE=Vulkan0 \
  -e LLAMA_ARG_N_GPU_LAYERS=999 \
  -e LLAMA_ARG_CTX_SIZE=131072 \
  -e LLAMA_ARG_CACHE_TYPE_K=q8_0 \
  -e LLAMA_ARG_CACHE_TYPE_V=q4_0 \
  -e LLAMA_ARG_FLASH_ATTN=on \
  -e LLAMA_ARG_SPEC_DRAFT_MODEL=/models/mtp-Qwen3.8-27B-Q4_0.gguf \
  -e LLAMA_ARG_SPEC_TYPE=draft-mtp \
  -e LLAMA_ARG_SPEC_DRAFT_N_MAX=4 \
  -e LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1 \
  -e LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q8_0 \
  -e LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q4_0 \
  -e LLAMA_ARG_REASONING=off \
  -e 'LLAMA_ARG_CHAT_TEMPLATE_KWARGS={"enable_thinking":false,"preserve_thinking":false}' \
  -e LLAMA_ARG_N_PARALLEL=1 \
  -e LLAMA_ARG_TEMPERATURE=0.7 \
  -e LLAMA_ARG_TOP_P=0.80 \
  -e LLAMA_ARG_TOP_K=20 \
  -e LLAMA_ARG_MIN_P=0.0 \
  -e LLAMA_ARG_PRESENCE_PENALTY=1.5 \
  -e LLAMA_ARG_FREQUENCY_PENALTY=0.0 \
  -e LLAMA_ARG_REPEAT_PENALTY=1.0 \
  -e LLAMA_ARG_HOST=0.0.0.0 \
  -e LLAMA_ARG_PORT=8080 \
  "$IMG" "$@"
# "$@" is only ever a log-verbosity flag (-lv 4); no sampling/config flag is passed.

echo "started $NAME from $IMG"
