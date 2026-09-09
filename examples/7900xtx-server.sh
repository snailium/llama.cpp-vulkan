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

set -euo pipefail

MODEL=${MODEL:-/models/Qwen3.8-27B-Q4_K_M.gguf}
CTX=${CTX:-32768}
KV=${KV:-q8_0}
DEVICE=${DEVICE:-0}   # vulkaninfo --summary tells you which index is the 7900 XTX

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
