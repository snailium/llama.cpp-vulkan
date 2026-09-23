# RX 7900 XTX Vulkan context ceiling: the cliff is at ~287 K, not 128 K

**Date:** 2026-09-23 · **Card:** AMD Radeon RX 7900 XTX (24 GB, NAVI31 / RDNA3) · **Backend:** Vulkan / RADV
**Image:** `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-dev-m26.2-b11117-20260923-0149`
**Model:** Qwen3.8-27B-Q4_K_M + MTP4 draft (`mtp-...-Q4_0`) · **KV:** q4_0 K and V · **flash-attn:** on
**Runner:** [`xtx-ctx-scan.sh`](../../../scripts/xtx-ctx-scan.sh) — isolated container, RADV pinned via `VK_DRIVER_FILES`, `--parallel 1`.

## Headline

**The production `--ctx-size 131072` is far below this card's real limit.** The
context ceiling is **between 292864 and 293888 tokens (~287 K)** — **2.24x** the
configured value. Below the cliff, decode is flat at **52-58 t/s**; above it,
decode collapses **6.5x to ~8 t/s** even though free VRAM *increases*.

| ctx | free VRAM | decode | draft accept | verdict |
|---|---|---|---|---|
| 131072 (production) | 2676 MiB | 57.8 t/s | 40.3% | ✅ |
| 163840 | 2000 MiB | 53.0 t/s | 34.0% | ✅ |
| 196608 | 1324 MiB | 52.9 t/s | 33.6% | ✅ |
| 229376 | 648 MiB | 58.3 t/s | 39.9% | ✅ |
| 262144 (256 K) | 300 MiB | **58.0 t/s** | 42.6% | ✅ |
| 270336 | 138 MiB | 55.4 t/s | 38.4% | ✅ |
| 278528 | 283 MiB | 54.4 t/s | 39.1% | ✅ |
| 286720 | 132 MiB | 53.2 t/s | 35.4% | ✅ |
| **290816** | **57 MiB** | **62.3 t/s** | 47.0% | ✅ |
| **292864** | **19 MiB** | **51.8 t/s** | 38.2% | ✅ **last good** |
| **293888** | 451 MiB | **8.0 t/s** | 34.7% | ❌ **first bad** |
| 294400 | 438 MiB | 9.0 t/s | 43.2% | ❌ |
| 294912 (288 K) | 429 MiB | 8.0 t/s | 35.5% | ❌ |
| 327680 (320 K) | 144 MiB | 8.6 t/s | 39.9% | ❌ |
| 393216 (384 K) | 191 MiB | 5.0 t/s | 36.9% | ❌ |

**The ceiling is ~287 K tokens** (292864 works, 293888 does not — a 1024-token
step). Every point above it still *loads* and still answers; it is only decode
that collapses.

## The cliff is NOT a VRAM-exhaustion cliff

This is the counter-intuitive part, and it is why the ceiling was previously
mis-estimated as 128 K.

**Free VRAM goes UP when performance collapses:**

| | ctx | free VRAM | decode |
|---|---|---|---|
| last good | 292864 | **19 MiB** | **51.8 t/s** |
| first bad | 293888 | **451 MiB** | **8.0 t/s** |

The last-good point runs fine with **19 MiB** free; the first-bad point has
**432 MiB more headroom** and is 6.5x slower. A memory-exhaustion story cannot
explain that — and neither can a KV-size story, because 292864→293888 changes KV
by well under 0.1 GiB.

Direct VRAM measurement across the boundary confirms it:

| ctx | VRAM actually used |
|---|---|
| 292864 | 23166 MiB |
| 293888 | 23185 MiB |

**19 MiB apart.** Both are pinned just under the card's 24560 MiB. So the card is
equally full on both sides; what changes is *what llama.cpp does with the
allocation it could not fit*.

**Most likely mechanism:** above the boundary llama.cpp's Vulkan allocator stops
placing part of the working set in VRAM and falls back to host memory, so each
decoded token has to cross PCIe for that portion. That produces exactly this
signature — a large, sudden, uniform decode slowdown with no OOM, no crash, and
free VRAM that paradoxically *increases* (the fallback freed VRAM). This report
does **not** prove that mechanism; it is the hypothesis that fits the data, and
the free-VRAM inversion is the evidence for it.

## Why this matters for production

Production runs `--ctx-size 131072` + q4_0 KV + MTP4, which the 2026-09-16 work
adopted specifically to avoid the old "218 MiB free → 10.5 t/s" cliff. **That
concern no longer applies to the current build.** At 131072 the card now has
2676 MiB free and 57.8 t/s — it is running with ~2.6 GiB of unused headroom while
the ceiling sits at 287 K.

**Recommended operating point: 262144 (256 K).** Rationale:

- **300 MiB free and 58.0 t/s** — performance identical to 131072 within noise.
- **2x the usable context** for agentic workloads that currently truncate.
- **29 K tokens of margin** below the 292864 last-good point. The margin matters
  because the boundary is sharp and workload-dependent: prompt-cache entries,
  vision mmproj buffers, and concurrent slots all consume from the same pool.
  290816 (57 MiB free) and 292864 (19 MiB free) *worked in this test* but leave no
  room for a second allocation — do not configure at the edge.

262144 also keeps the "~0.3 GB free is workable" rule of thumb from the 2026-09-16
report, which remains the right guardrail.

## Method and caveats

1. **Isolated container per point.** Each ctx value ran in a fresh container on
   the XTX only (`--device /dev/dri` plus `VK_DRIVER_FILES=radeon_icd.json` to
   pin RADV and exclude the Intel device), then was removed before the next point,
   so no VRAM leaked between measurements.
2. **`--parallel 1` throughout.** Note the image defaults to `n_parallel=4` +
   `kv_unified=true`; the scan pins 1 slot so the ctx value is the real context,
   not a 4-way-shared pool. **Production also runs `--parallel 1`.**
3. **Decode measured on a 256-token generation**, temperature 0.7, same prompt at
   every point. Draft acceptance is reported alongside because MTP changes the
   effective speed and acceptance varies with depth.
4. **Free VRAM read from sysfs** (`mem_info_vram_used`), not from the loader log —
   the current image no longer prints a buffer breakdown at default verbosity.
5. **Not a depth scan.** This measures the *configured* context ceiling, not
   decode speed at depth. Deep-context decode decay on this card is a separate
   question; a 128 K-configured run with a 120 K prompt is not what was measured
   here.
6. **Interference.** A B70 test container (`b70-test-issue20`) was running for the
   first point and exited before the rest; it mounts the whole `/dev/dri` and
   shares host RAM/swap. Swap stayed at 1.3-2.1 GB throughout, well below the
   7/7-full condition that previously produced `ExitCode=137`. The boundary points
   (290816-294912) were all measured with the B70 container gone.

## Production state

`xtx-vulkan` was stopped for this scan and **restored** afterwards. Restoring it
tripped SMG's circuit breaker exactly as the skill warns: `/health` returned ok
while `/workers` reported `status: failed`. `docker restart smg` cleared it, and
end-to-end routing through `:40114` was verified returning `ok`.

`b70-sycl` remains in its pre-existing `Exited (0)` state — it was not running
before the scan and was not touched.

## Follow-ups

- **Consider raising production ctx to 262144** — but validate with a real
  deep-context run first, since this scan measured configured ceiling, not
  sustained decode at depth.
- **Re-scan after the boundary moves.** The cliff is a property of this
  image + model + KV combination; a KV-precision change (q4_0 → q8_0) or a
  different draft size shifts it. If any of those change, re-measure.
- **The 293888 free-VRAM inversion is worth an upstream look.** A config that
  silently falls back to host memory while reporting *more* free VRAM is a bad
  failure mode: nothing in the logs flags it, and the only symptom is 6.5x slower
  decode.
