# Golden Configuration — llama.cpp Vulkan

The canonical, tested production configuration for this repository's image.
Everything here was verified against a live container, not copied from an example
script. **When this document and `examples/*.sh` disagree, this document wins** —
the example scripts are illustrative starting points, this is the record of what
actually runs.

Last verified: **2026-09-20**.

---

## 1. Image

| Field | Value |
|---|---|
| Registry | `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan` |
| Stable channel | `:stable` (plus a `:vX.Y` release tag) |
| Dev channel | `:server-dev` |
| Last known-good | **`:latest`** — see §1.1 |
| Entrypoint | image default — **never override it** |

This image ships **both** ANV (Intel) and RADV (AMD) ICDs; the `--device` index
plus an optional `VK_DRIVER_FILES` selects the card. That is why one image serves
two targets.

### 1.1 Tag semantics

| Tag | Moves when | Meaning |
|---|---|---|
| `:server-dev` | a flag: `promote-vulkan-image.sh <digest> "" <repo> dev` | current dev channel |
| `:stable` + `:vX.Y` | `promote-vulkan-image.sh <digest> vX.Y` | stable release |
| **`:latest`** | **any** promote — but only if the candidate is **newer** | last tested + promoted image, on **either** channel |

**`:latest` is monotonic by image build date.** It tracks the most recently
*built* image that we tested and promoted, and it never moves backwards: promoting
an older digest (e.g. re-promoting a stable release after a dev build has already
advanced `:latest`) leaves `:latest` where it is and prints
`⊘ :latest NOT moved — this image is OLDER than :latest`.

The point of the rule: `docker pull …:latest` must never hand someone bits older
than what they already got. Decide by **image build time**, not by tag name or
promote order — a dev tag can legitimately point at newer bits than a stable tag
promoted afterwards.

`promote-vulkan-image.sh` applies this automatically. Set `LATEST=0` to skip it.

---

## 2. Targets

This image has **two supported targets**, and they do **not** share a config.
The 7900 XTX's 24 GB is the binding constraint; the B70's 32 GB allows a wider KV.

| | **B70** (Intel Arc Pro B70) | **7900 XTX** (AMD RX 7900 XTX) |
|---|---|---|
| VRAM | 32 GB | **24 GB (24560 MiB)** |
| `--ctx-size` | 98304 | 131072 |
| KV (`--cache-type-k/-v`) | **f16** | **q4_0** |
| MTP draft model | `mtp-...-Q4_0.gguf` | `mtp-...-Q4_0.gguf` |
| `--spec-draft-n-max` | 3 | 4 |
| ICD pin | `intel_icd.json` (ANV) | `radeon_icd.json` (RADV) |
| Verification | **not yet fully verified** (see §6) | verified 2026-09-16 |

> ⚠️ **Never run the XTX config on the B70 or vice versa.** They differ in context
> length and KV precision; using one on the other card either fails to fit or
> silently changes the numbers.

---

## 3. Container spec

```bash
docker run -d --name <name> \
  --device /dev/dri \
  -v <models-dir>:/models:ro \
  -p <host-port>:8080 \
  -e LLAMA_ARG_HOST=0.0.0.0 \
  -e VK_DRIVER_FILES=/usr/share/vulkan/icd.d/<icd>.json \
  --restart no \
  <image> \
  <server args — see §4>
```

| Setting | Value | Why |
|---|---|---|
| Device | `/dev/dri` (whole directory) | survives card index changes; a scoped single render node is safer but less portable |
| Models | host dir mounted **read-only** at `/models` | weights never need to be writable |
| `VK_DRIVER_FILES` | one ICD json | **required on a mixed Intel+AMD box** — otherwise the loader enumerates both vendors and `--device 0` is ambiguous |
| `LLAMA_ARG_HOST` | `0.0.0.0` | listen inside the container namespace |
| `--restart` | `no` | deliberate: GPU containers come up consciously after host/PCIe events |

---

## 4. Server arguments (exact)

### 7900 XTX — verified production config

```bash
-m /models/Qwen3.8-27B-Q4_K_M.gguf
--mmproj /models/mmproj-Qwen3.8-27B-Q8_0.gguf
--no-mmproj-offload
--image-min-tokens 1024
--device Vulkan0
--n-gpu-layers 999
--ctx-size 131072
--cache-type-k q4_0
--cache-type-v q4_0
--flash-attn on
--spec-draft-model /models/mtp-Qwen3.8-27B-Q4_0.gguf
--spec-type draft-mtp
--spec-draft-n-max 4
--spec-draft-p-min 0.1
--spec-draft-type-k q4_0
--spec-draft-type-v q4_0
--reasoning off
--chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}'
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
--parallel 1
--host 0.0.0.0 --port 8080
```

With `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json`.

### B70 — intended config (see §6 for status)

```bash
-m /models/Qwen3.8-27B-Q4_K_M.gguf
--device Vulkan0
--n-gpu-layers 999
--ctx-size 98304
--cache-type-k f16
--cache-type-v f16
--flash-attn auto
--spec-draft-model /models/mtp-Qwen3.8-27B-Q4_0.gguf
--spec-type draft-mtp
--spec-draft-n-max 3
--spec-draft-p-min 0.1
--reasoning off
--chat-template-kwargs '{"enable_thinking":false,"preserve_thinking":false}'
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
--host 0.0.0.0 --port 8080
```

With `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json`.

---

## 5. Why the XTX config deviates from the SYCL golden

Both deviations are forced by 24 GB, and both were measured rather than assumed:

| Config tested | ctx | KV | MTP draft | Free VRAM | Decode |
|---|---|---|---|---|---|
| original | 32768 | q8_0 | none | 5245 MiB | 35.5 t/s |
| full SYCL-golden attempt | 131072 | q4_0 | Q8_0 (3.16 GB) | **218 MiB** | **10.5 t/s** ❌ |
| ctx only | 131072 | q4_0 | none | 3946 MiB | 35.5 t/s |
| ctx halved | 65536 | q4_0 | Q8_0 | 717 MiB | 44-53 t/s |
| **adopted** | **131072** | **q4_0** | **Q4_0 (1.37 GB)** | **298-389 MiB** | **48-58 t/s** |

**There is a sharp VRAM cliff.** The complete SYCL-golden set *loads* with 218 MiB
free and decode **collapses 3.4x to 10.5 t/s** while the GPU still reports 99% busy
— spill/thrash, not a kernel limit. **~0.3 GB free is workable; ~0.2 GB is not.**

**The Q4_0 draft is what makes 131072 + MTP fit at all** (1.37 GB vs the Q8_0
module's 3.16 GB). Dropping the draft KV to q4_0 is the consistent companion change.

> ⚠️ **Comparability caveat.** q4_0 KV is a *lower precision* than the SYCL golden's
> q8_0, and lower precision also means less KV read bandwidth. **Vulkan-vs-SYCL
> decode numbers are therefore not a pure backend comparison.** State the KV
> precision next to every cross-backend number.

---

## 6. Verification status

| Target | Status |
|---|---|
| **7900 XTX** | ✅ Full suite verified 2026-09-16; promoted to `:v0.4.1` |
| **B70 (Vulkan)** | ⚠️ **Not yet verified end-to-end.** `benchmark/configs/b70-mtp3-q4-96k.md` marks the MTP config "expected, unverified"; no public B70 Vulkan+MTP numbers exist. The 96k/f16 numbers come from `b70-f16-96k.md`. Treat any B70 Vulkan figure as provisional until a full suite run lands. |

Do not promote a Vulkan image on B70 evidence alone while this row reads unverified.

---

## 7. Verification steps

1. **Record the digest**, not just the tag: `docker inspect <name>` / the repo digest.
   Tags move; a digest is the durable record of what was tested.
2. **Free the card.** Both production containers mount `/dev/dri` as a whole, so the
   other card is exposed even when untouched. Baseline the other container's
   `RestartCount` **before** the run and re-check after.
3. **Read the offload line** in the loader log (`n_gpu_layers`) before trusting any
   number — a silently CPU-offloaded run produces plausible but meaningless timings.
4. **Read free VRAM** from the loader log. A config that merely *loads* is not a
   config that *performs* (§5).
5. Run the full suite (t1-t5 + V1-V3) per the `backend-test-suite` skill, with the
   card-specific half from `xtx-backend-test` or `b70-backend-test`.
6. Restore the production container and verify it actually serves.

---

## 8. Change log

| Date | Change |
|---|---|
| 2026-09-20 | Initial golden record. XTX config taken from the live production container (`xtx-vulkan`); B70 config from `benchmark/configs/b70-mtp3-q4-96k.md` + `b70-f16-96k.md`, marked unverified. |
| 2026-09-25 | Added `:latest` = last tested+promoted image (monotonic by build date) and dev/stable channel split to the promote script; §1.1 tag semantics. |
