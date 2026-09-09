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

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
CTX=${CTX:-98304}
KV=${KV:-f16}
DEVICE=${DEVICE:-0}   # vulkaninfo --summary tells you which index is the B70

TEMP=${TEMP:-0.7}
TOPP=${TOPP:-0.80}
TOPK=${TOPK:-20}
MINP=${MINP:-0.0}
PRES=${PRES:-1.5}
FREQ=${FREQ:-0.0}
REPEAT=${REPEAT:-1.0}

exec llama-server \
  -m "$MODEL" \
  --device "$DEVICE" \
  --n-gpu-layers 999 \
  --ctx-size "$CTX" \
  --cache-type-k "$KV" \
  --cache-type-v "$KV" \
  --flash-attn auto \
  --temp "$TEMP" --top-p "$TOPP" --top-k "$TOPK" --min-p "$MINP" \
  --presence-penalty "$PRES" --frequency-penalty "$FREQ" --repeat-penalty "$REPEAT" \
  --port 8080 --host 0.0.0.0 \
  "$@"
