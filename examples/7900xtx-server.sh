#!/usr/bin/env bash
# Recommended launch for Qwen3.8-27B (Q4_K_M) on a single AMD RX 7900 XTX — VULKAN backend.
# Config: benchmark/configs/7900xtx-q8-32k.md (q8_0 KV + 32k, no draft — 24 GB ceiling).
# Sampling: OFFICIAL Qwen3.8-27B instruct/non-thinking params (HF model card) —
#   presence_penalty=1.5 is Qwen's fix for verbosity/rambling in non-thinking mode.
#   Override any of these by exporting TEMP/TOPP/TOPK/MINP/PRES/FREQ/REPEAT before running.
#
# Env notes:
#   - No mandatory env vars; the loader finds RADV automatically.
#   - On a mixed Intel+AMD box, force the ICD: VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
#   - 27B-class at >32k is untested on this card — raise CTX only after verifying free VRAM
#     in the loader log (TUNING §5).
#
# ---------------------------------------------------------------------------
# CONFIGURATION IS DELIVERED AS LLAMA_ARG_* ENVIRONMENT VARIABLES, NOT FLAGS.
#
# llama.cpp maps every server argument to an LLAMA_ARG_* variable, so the config
# can be an environment block — the same shape docker-compose.yml uses. Passing
# no flags at all is deliberate.
#
# ⚠️ MINIMUM VERSION — READ BEFORE CHANGING THE IMAGE TAG
#
#   | variable group                              | floor        |
#   |---------------------------------------------|--------------|
#   | model / ctx / KV / flash-attn / offload /   | older than   |
#   | device / n-gpu-layers / parallel / host/port| v0.4.1       |
#   | **sampling: TEMPERATURE, TOP_P, MIN_P,      | **>= b11078**|
#   | PRESENCE_PENALTY, FREQUENCY_PENALTY,        |              |
#   | REPEAT_PENALTY**                            |              |
#
# The six sampling variables were added in commit e0dff5847 (#27380), first
# shipped in **b11078**. So:
#
#   * **v0.4.1 (b10964) and older do NOT support them** — they are silently
#     ignored and the server runs with its own defaults (temp 0.8, top_p 0.95,
#     ...), changing output quality with no error at all. **The `:v0.4.1` /
#     `:stable` Vulkan image is in this group** — it is built from llama.cpp
#     b29c606, which is exactly v0.4.1.
#   * **Any dev build before b11078 has the same gap.**
#   * **v0.5.0 (>= b11146) is fine**, as is `server-dev` built from b11078+.
#
# If you must run an image older than b11078, set USE_SAMPLING_FLAGS=1 and the
# six sampling values are passed as command-line flags instead (flags win over
# any env var, so both paths stay correct).
# ---------------------------------------------------------------------------

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
CTX=${CTX:-32768}
KV=${KV:-q8_0}
DEVICE=${DEVICE:-0}   # vulkaninfo --summary tells you which index is the 7900 XTX
PORT=${PORT:-8080}
HOSTADDR=${HOSTADDR:-0.0.0.0}

TEMP=${TEMP:-0.7}
TOPP=${TOPP:-0.80}
TOPK=${TOPK:-20}
MINP=${MINP:-0.0}
PRES=${PRES:-1.5}
FREQ=${FREQ:-0.0}
REPEAT=${REPEAT:-1.0}

# Set to 1 for images older than b11078, where the sampling env vars do not exist.
USE_SAMPLING_FLAGS=${USE_SAMPLING_FLAGS:-0}

# --- server configuration, as LLAMA_ARG_* ----------------------------------
export LLAMA_ARG_MODEL="$MODEL"
export LLAMA_ARG_DEVICE="$DEVICE"
export LLAMA_ARG_N_GPU_LAYERS=999
export LLAMA_ARG_CTX_SIZE="$CTX"
export LLAMA_ARG_CACHE_TYPE_K="$KV"
export LLAMA_ARG_CACHE_TYPE_V="$KV"
export LLAMA_ARG_FLASH_ATTN=auto
export LLAMA_ARG_HOST="$HOSTADDR"
export LLAMA_ARG_PORT="$PORT"

# --- sampling: env vars only on llama.cpp >= b11078 ------------------------
if [ "$USE_SAMPLING_FLAGS" = "1" ]; then
  SAMPLING_FLAGS=(
    --temp "$TEMP" --top-p "$TOPP" --top-k "$TOPK" --min-p "$MINP"
    --presence-penalty "$PRES" --frequency-penalty "$FREQ" --repeat-penalty "$REPEAT"
  )
else
  SAMPLING_FLAGS=()
  export LLAMA_ARG_TEMPERATURE="$TEMP"
  export LLAMA_ARG_TOP_P="$TOPP"
  export LLAMA_ARG_TOP_K="$TOPK"
  export LLAMA_ARG_MIN_P="$MINP"
  export LLAMA_ARG_PRESENCE_PENALTY="$PRES"
  export LLAMA_ARG_FREQUENCY_PENALTY="$FREQ"
  export LLAMA_ARG_REPEAT_PENALTY="$REPEAT"
fi

exec llama-server "${SAMPLING_FLAGS[@]}" "$@"
