#!/usr/bin/env bash
# Recommended launch for Qwen3.8-27B (Q4_K_M) on a single Intel Arc Pro B70 — VULKAN backend.
# Config: benchmark/configs/b70-f16-96k.md (f16 KV + 96k, no draft).
# Sampling: OFFICIAL Qwen3.8-27B instruct/non-thinking params (HF model card) —
#   presence_penalty=1.5 is Qwen's fix for verbosity/rambling in non-thinking mode.
#   Override any of these by exporting TEMP/TOPP/TOPK/MINP/PRES/FREQ/REPEAT before running.
#
# Env notes:
#   - No mandatory env vars for the basic Vulkan path; the loader finds ANV automatically.
#   - On a mixed Intel+AMD box, force the ICD: VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json
#   - Read the n_gpu_layers line in the server log before trusting any benchmark (TUNING §5).
#
# ⚠️ The B70 on Vulkan is NOT the recommended production pairing — SYCL is. A
#    dual-target run measured ~8x deep-context decode collapse on this card
#    (36 -> 4.5 t/s at 61 K), while the XTX holds 53-70 t/s. See GOLDEN-CONFIG §6.
#
# ---------------------------------------------------------------------------
# CONFIGURATION IS DELIVERED AS LLAMA_ARG_* ENVIRONMENT VARIABLES, NOT FLAGS.
#
# llama.cpp maps every server argument to a LLAMA_ARG_* variable, so the config
# can be an environment block — the same shape docker-compose.yml uses. Passing
# no flags at all is deliberate.
#
# ⚠️ MINIMUM VERSION — READ BEFORE CHANGING THE IMAGE TAG
#
# The six sampling variables (TEMPERATURE, TOP_P, MIN_P, PRESENCE_PENALTY,
# FREQUENCY_PENALTY, REPEAT_PENALTY) were added in commit e0dff5847 (#27380),
# first shipped in **b11078**. Everything else here predates v0.4.1.
#
#   * **v0.4.1 (b10964) and older do NOT support them** — silently ignored, and
#     the server runs with its own defaults (temp 0.8, top_p 0.95, ...). The
#     `:v0.4.1` / `:stable` Vulkan image is built from llama.cpp b29c606, which
#     is exactly v0.4.1, so it is in this group.
#   * **v0.5.0 (>= b11146) is fine.**
#
# For an older image set USE_SAMPLING_FLAGS=1; the six are then passed as flags.
# ---------------------------------------------------------------------------

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
CTX=${CTX:-98304}
KV=${KV:-f16}
DEVICE=${DEVICE:-0}   # vulkaninfo --summary tells you which index is the B70
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
