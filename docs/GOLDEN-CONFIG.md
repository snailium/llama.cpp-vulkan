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
| Production tag | `:v0.4.1` (also `:stable`) |
| Entrypoint | image default — **never override it** |

This image ships **both** ANV (Intel) and RADV (AMD) ICDs; the `--device` index
plus an optional `VK_DRIVER_FILES` selects the card. That is why one image serves
two targets.

---

## 2. Targets

This image has **two supported targets**, and they do **not** share a config.
The 7900 XTX's 24 GB is the binding constraint; the B70's 32 GB allows a wider KV.

| | **B70** (Intel Arc Pro B70) | **7900 XTX** (AMD RX 7900 XTX) |
|---|---|---|
| VRAM | 32 GB | **24 GB (24560 MiB)** |
| `--ctx-size` | **131072** | 131072 |
| KV (`--cache-type-k/-v`) | **f16** | **q4_0** |
| MTP draft model | `mtp-...-Q4_0.gguf` | `mtp-...-Q4_0.gguf` |
| `--spec-draft-n-max` | 3 | 4 |
| `--parallel` | **1** | **1** |
| mmproj placement | **GPU** (no `--no-mmproj-offload`) | **CPU** (`--no-mmproj-offload`) |
| ICD pin | `intel_icd.json` (ANV) | `radeon_icd.json` (RADV) |
| Verification | verified 2026-09-22 (see §6) | verified 2026-09-16 |

> ⚠️ **Never run the XTX config on the B70 or vice versa.** They differ in KV
> precision and mmproj placement; using one on the other card either fails to fit or
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

The canonical form is **`LLAMA_ARG_*` environment variables**, because llama.cpp
maps every server argument to one. `docker-compose.yml` and `examples/*.sh` use
this form and pass **no flags at all**.

### 7900 XTX — verified production config

```bash
LLAMA_ARG_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
LLAMA_ARG_MMPROJ=/models/mmproj-Qwen3.8-27B-Q8_0.gguf
LLAMA_ARG_MMPROJ_OFFLOAD=false          # == --no-mmproj-offload
LLAMA_ARG_IMAGE_MIN_TOKENS=1024
LLAMA_ARG_DEVICE=Vulkan0
LLAMA_ARG_N_GPU_LAYERS=999
LLAMA_ARG_CTX_SIZE=131072
LLAMA_ARG_CACHE_TYPE_K=q4_0
LLAMA_ARG_CACHE_TYPE_V=q4_0
LLAMA_ARG_FLASH_ATTN=on
LLAMA_ARG_SPEC_DRAFT_MODEL=/models/mtp-Qwen3.8-27B-Q4_0.gguf
LLAMA_ARG_SPEC_TYPE=draft-mtp
LLAMA_ARG_SPEC_DRAFT_N_MAX=4
LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1
LLAMA_ARG_SPEC_DRAFT_TYPE_K=q4_0
LLAMA_ARG_SPEC_DRAFT_TYPE_V=q4_0
LLAMA_ARG_REASONING=off
LLAMA_ARG_CHAT_TEMPLATE_KWARGS={"enable_thinking":false,"preserve_thinking":false}
LLAMA_ARG_N_PARALLEL=1
LLAMA_ARG_TEMPERATURE=0.7
LLAMA_ARG_TOP_P=0.80
LLAMA_ARG_TOP_K=20
LLAMA_ARG_MIN_P=0.0
LLAMA_ARG_PRESENCE_PENALTY=1.5
LLAMA_ARG_FREQUENCY_PENALTY=0.0
LLAMA_ARG_REPEAT_PENALTY=1.0
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=8080
```

With `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json`.

### ⚠️ Minimum llama.cpp version for the env-var form

**The six sampling variables are NOT supported before b11078.**

| Variable group | Minimum version |
|---|---|
| model / device / n-gpu-layers / ctx / KV / flash-attn / mmproj / spec-decode / parallel / host / port | older than v0.4.1 |
| **`LLAMA_ARG_TEMPERATURE`, `TOP_P`, `MIN_P`, `PRESENCE_PENALTY`, `FREQUENCY_PENALTY`, `REPEAT_PENALTY`** | **>= b11078** |

The six were added in commit `e0dff5847` ("args: add env vars for temperature,
top-p, min-p and penalties", #27380), first shipped in **b11078**.

Consequences — note that **this repository's own published images are affected**:

- **v0.4.1 (b10964) and older does not support them.** They are **silently
  ignored** — no warning, no error — and the server falls back to its defaults
  (`temp 0.8`, `top_p 0.95`, ...), changing output quality with no signal.
- **`:v0.4.1` and `:stable` are in this group**: both are built from llama.cpp
  `b29c606`, which is exactly v0.4.1. Verified by reading the tag.
- **Any dev build before b11078 has the same gap.** `:server-dev` built from
  b11078+ is fine, as is **v0.5.0 (>= b11146)**.

For an older image, pass the six as flags — they take precedence over the env
vars, so both forms coexist safely:

```bash
--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
--presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0
```

`examples/*.sh` does this automatically via `USE_SAMPLING_FLAGS=1`.

Verify what the server actually accepted rather than trusting the config:

```bash
curl -s http://127.0.0.1:8080/props | python3 -c "
import json,sys; d=json.load(sys.stdin)['default_generation_settings']
print('n_ctx =', d['n_ctx'])
for k in ('top_p','top_k','min_p','presence_penalty','frequency_penalty','repeat_penalty'):
    print(f'  {k:20} = {d[\"params\"].get(k)}')
"
```

### B70 — testable config (see §6 for status)

```bash
LLAMA_ARG_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
LLAMA_ARG_MMPROJ=/models/mmproj-Qwen3.8-27B-Q8_0.gguf
LLAMA_ARG_IMAGE_MIN_TOKENS=1024
LLAMA_ARG_DEVICE=Vulkan0
LLAMA_ARG_N_GPU_LAYERS=999
LLAMA_ARG_CTX_SIZE=131072
LLAMA_ARG_CACHE_TYPE_K=f16
LLAMA_ARG_CACHE_TYPE_V=f16
LLAMA_ARG_FLASH_ATTN=auto
LLAMA_ARG_SPEC_DRAFT_MODEL=/models/mtp-Qwen3.8-27B-Q4_0.gguf
LLAMA_ARG_SPEC_TYPE=draft-mtp
LLAMA_ARG_SPEC_DRAFT_N_MAX=3
LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1
LLAMA_ARG_REASONING=off
LLAMA_ARG_CHAT_TEMPLATE_KWARGS={"enable_thinking":false,"preserve_thinking":false}
LLAMA_ARG_N_PARALLEL=1
LLAMA_ARG_TEMPERATURE=0.7
LLAMA_ARG_TOP_P=0.80
LLAMA_ARG_TOP_K=20
LLAMA_ARG_MIN_P=0.0
LLAMA_ARG_PRESENCE_PENALTY=1.5
LLAMA_ARG_FREQUENCY_PENALTY=0.0
LLAMA_ARG_REPEAT_PENALTY=1.0
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=8080
```

Note the absence of `LLAMA_ARG_MMPROJ_OFFLOAD`: the B70 leaves the projector on
the GPU (see (b) below), so it is simply not set.

With `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json`.

> ⚠️ **The six sampling variables need llama.cpp >= b11078** — same floor as the
> XTX block above. `USE_SAMPLING_FLAGS=1` covers older images.

> **Changed 2026-09-22 (B70 block):** three edits, all measured.
> **(a)** `--ctx-size` 98304 → **131072**, so the B70's ceiling matches the XTX and
> the SYCL production config instead of sitting arbitrarily below both.
> **(b)** `--no-mmproj-offload` **removed**, putting the vision projector on the GPU.
> This was the single biggest win in the run: **V3 prefill 48.6 → 3882.7 t/s and
> TTFT 85.9 → 1.1 s**, V1 53.4 → 232.3 t/s, V2 95.7 → 290.9 t/s. Cost: 248 MiB VRAM.
> **(c)** `--parallel 1` added; the block previously omitted it, so llama-server
> auto-selected `n_parallel=4, kv_unified=true` while the XTX pinned 1 — an
> unintended asymmetry in a "dual-target" image.
>
> ⚠️ **The startup log will print a fit warning that is a FALSE ALARM:**
> `cannot meet free memory target of 1872 MiB, need to reduce device memory by 1483 MiB`
> → `W failed to fit params to free device memory`. This is llama.cpp's
> conservation pre-check using mmproj's **848 MiB worst-case estimate** while its
> real tensors need only 248 MiB, and demanding 1872 MiB headroom.
> **Measured headroom via nvtop is 3.24 GB** (llama-server 28824 MiB + Xvfb 518 MiB
> of a 32656 MiB card), so the config fits comfortably. Do not read this warning as
> an OOM or as a reason to lower ctx/KV without measuring first.
>
> Measured VRAM accounting at ctx 131072 f16 (server-side buffers): model 17402 +
> KV 8192 + RS 599 + compute 260 + draft 775 + draft KV 512 + draft compute 200 +
> mmproj 248 = **28188 MiB**; nvtop reports 28824 MiB, the ~636 MiB gap being
> mmproj's worst-case-vs-real difference.

> **Fixed 2026-09-20:** the vision flags (`--mmproj`, `--no-mmproj-offload`,
> `--image-min-tokens 1024`) were **absent from this block since the file's first
> commit** — an omission, not a deliberate exclusion. Without them the server
> rejects images with `image input is not supported - hint: ... provide the mmproj`,
> which silently makes V1-V3 unrunnable on the B70. The B70's vision support was
> already proven in `benchmark/results/2026-09-10-vulkan-dev-b10883.md`
> (`mmproj 65/65` on the B70). The block had been transcribed from
> `benchmark/configs/b70-*.md`, which never carried these flags — unlike the XTX
> block, which was dumped from the live production container.

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
| **7900 XTX** | ✅ Full suite verified 2026-09-16, 2026-09-20 (b11064) and again **2026-09-22 (b11117, Mesa 26.2.3)** — t1-t5 + V1-V3 all PASS, 0 crashes. Promoted to `:server-dev` (digest `3e520caa…`). Decode 70-98 t/s; held **74.8 t/s at ~75 K context**. |
| **B70 (Vulkan)** | ⚠️ **Verified 2026-09-20 and twice on 2026-09-22 (b11117), but still NOT recommended for production *pending re-evaluation*.** Three full-suite runs, t1-t5 + V1-V3 all PASS, 0 crashes, 0 truncation. **The ~8x deep-context decode collapse is largely FIXED in b11117**: measured with the `depth_scan.py` A/B — 64 K decode **4.5 → 24.0 t/s (5.3x)**, decay 1k→64k **8.62x → 1.80x**, while prefill/TTFT/acceptance are unchanged (a decode-path fix). `:v0.4.1` (b11064) reproduced the old collapse exactly, so this is not a measurement artifact. See `benchmark/results/2026-09-23-b70-deep-context-collapse-fixed.md`. |

> **B70 recommendation is now under revision (2026-09-23).** The "~8x collapse" that
> justified *"use SYCL, not Vulkan, on this card"* no longer reproduces on b11117.
> Decode at 64 K is 24 t/s, versus **4.5 t/s** on both b11064 and b10883. This does
> **not** automatically reverse the recommendation — the XTX still holds 74.8 t/s at
> ~75 K on the same image, and no-draft MTP behaviour at depth was not retested — but
> the B70-on-Vulkan pairing should be **re-evaluated rather than assumed dead**.

> **Fixed 2026-09-22:** vision (V1-V3) now runs on the B70. The `--mmproj` omission
> in the B70 block in §4 was corrected on 2026-09-20 and confirmed working by the
> b11117 run — the b11064 run had recorded V1-V3 as N/A (`image input is not
> supported`) on this card.
>
> **Open config asymmetry:** the XTX block pins `--parallel 1`, while the B70 block
> has no `--parallel`, so the B70 starts with
> `n_parallel = 4, kv_unified = true` → `n_slots = 4`. This is unintended and means
> the two cards are not run under the same slot policy. Throughput is not directly
> distorted (the harness is sequential), but a strict cross-card comparison inherits
> the caveat. State the B70's intent explicitly in §4.

### ⚠️ B70 recommendation: still SYCL, but RE-OPEN for review (2026-09-23)

The original reason for this recommendation was the **deep-context decode collapse**
("unusable as an agent backend at long context"). **On b11117 that collapse no longer
reproduces**: 64 K decode is **24.0 t/s** vs **4.5 t/s** on both b11064 and b10883,
measured with an identical `depth_scan.py` A/B. The paragraph above is therefore
**stale as a factual claim** — the Xe2 FA/GEMM path it said to wait for appears to
have landed for this card.

**The recommendation is retained only as the safe default, not as a measured
conclusion.** What still argues for SYCL:

- the XTX holds **74.8 t/s at ~75 K** on the same image versus the B70's 24 t/s;
- the B70's SYCL route is the established production path with more runtime history;
- MTP behaviour at depth (which inverted on Vulkan in the 2026-09-10 no-draft
  control) was **not** retested in b11117.

**Action:** re-evaluate B70-on-Vulkan with a matched-depth SYCL-vs-Vulkan A/B on the
current image before either retiring or reinstating this recommendation.

Do not promote a Vulkan image on B70 evidence alone.

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
| 2026-09-20 | **B70 block: added the missing vision flags** (`--mmproj`, `--no-mmproj-offload`, `--image-min-tokens 1024`). They had been absent since the first commit — a transcription omission, not a design choice (see §4 note). |
| 2026-09-20 | **§1/§6 updated after the b11064 dual-target run.** XTX re-verified and promoted to `:server-dev`. B70 marked verified-but-not-recommended: measured ~8x deep-context decode collapse → **use SYCL on the B70**. Version identity expressed as the llama.cpp `b` tag, not `vX.Y`. |
| 2026-09-23 | **§4 rewritten to the `LLAMA_ARG_*` environment-variable form**; `docker-compose.yml` and both `examples/*.sh` now pass **no flags at all**. Added the **version floor**: the six sampling variables need **>= b11078** (commit `e0dff5847`, #27380) and are *silently ignored* on v0.4.1 and older — which includes this repo's own `:v0.4.1` and `:stable` images, both built from llama.cpp `b29c606` (verified by reading the tag). `USE_SAMPLING_FLAGS=1` covers those. |
