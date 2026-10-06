# XTX Test Report — 7900 XTX (Vulkan) · NEW GOLDEN · `server-m26.2-v0.6.0-20261006-0021`

Date: 2026-10-06 · Host: `home-ai` `.101` · Card: AMD Radeon RX 7900 XTX (24 GB, NAVI31 / RDNA3)
Backend: Vulkan / RADV, Mesa 26.2.3 (`26.2.3~kisak1~r`) · ICD pinned `radeon_icd.json`
**Image digest:** `sha256:ab9b618a9736993a6dad5a46532adc273c8073206e36a963524bebb9c91cc69b`
**Harness digest:** `ghcr.io/snailium/dsh-container/dsh@sha256:c88327dd3686fa75b0195481a7a045e2f899345b8c79f54a6b23a8d57ddf29e5`
**Skill sha256:** `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` (8 prompts parsed at run time, none transcribed)
**Model:** Qwen3.8-27B-Q4_K_M · **MTP draft** `mtp-…-Q4_0.gguf`, K=4

**Scope: XTX only.** The B70 was deliberately excluded (user instruction). **Both prior runs of
this issue tested dual-target; this run tests the new XTX golden in isolation.**

> ⚠️ **This run tests a CHANGED GOLDEN, not the previously published one.** Both edits are
> documented in `docs/GOLDEN-CONFIG.md` §2/§4/§8 and were derived from the measurements in
> `test-issue10/REPORT.md`. The **published stable image is not modified** — the change is to
> the *documented configuration* and to the running `xtx-vulkan` stack's intent.

---

## Verdict

**The new golden is VALIDATED: it loads, fits, and every gating task that passed before still
passes, with materially better vision performance and no new failures.**

| Task | Result | vs. old golden (same image) |
|---|---|---|
| T1 | **PASS** | pass → pass |
| T2 | **PASS** | pass → pass |
| V1 | **PASS** | pass → pass |
| **V2** | **FAIL** | fail → fail (identical failure mode) |
| **V3** | **FAIL** | fail → fail (identical failure mode) |
| A1 | **PASS** | pass → pass |
| A2 | **PASS** | pass → pass |
| **A3** | **FAIL (unit error)** | **first run to produce a correct total — but mislabelled the unit** |

**Stability: 0 crashes, 0 of 154 releases truncated, `exit=0`, `RestartCount=0`,
`OOMKilled=false`.** Free VRAM **720 MiB**, stable throughout.

**The headline gain is vision**, and it is large and clean (§3).

---

## 1. The golden that was tested

```bash
LLAMA_ARG_MODEL=/models/Qwen3.8-27B-Q4_K_M.gguf
LLAMA_ARG_MMPROJ=/models/mmproj-Qwen3.8-27B-Q8_0.gguf
# LLAMA_ARG_MMPROJ_OFFLOAD deliberately ABSENT (defaults to enabled -> projector on GPU)
LLAMA_ARG_IMAGE_MIN_TOKENS=1024
LLAMA_ARG_DEVICE=Vulkan0
LLAMA_ARG_N_GPU_LAYERS=999
LLAMA_ARG_CTX_SIZE=131072
LLAMA_ARG_CACHE_TYPE_K=q8_0          # was q4_0
LLAMA_ARG_CACHE_TYPE_V=q4_0
LLAMA_ARG_FLASH_ATTN=on
LLAMA_ARG_SPEC_DRAFT_MODEL=/models/mtp-Qwen3.8-27B-Q4_0.gguf
LLAMA_ARG_SPEC_TYPE=draft-mtp
LLAMA_ARG_SPEC_DRAFT_N_MAX=4
LLAMA_ARG_SPEC_DRAFT_P_MIN=0.1
LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q8_0   # was misspelled -> silently f16
LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q4_0
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
```
with `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json`.

### Config verification (before any number was trusted)

```
llama_prepare_model_devices: using device Vulkan0 (AMD Radeon RX 7900 XTX (RADV NAVI31)) (0000:10:00.0)
load_tensors: offloaded 65/65 layers to GPU          # main
load_tensors: offloaded 66/66 layers to GPU          # draft
llama_kv_cache:    Vulkan0 KV buffer size =  3328.00 MiB   # main, q8_0 K / q4_0 V
llama_kv_cache:    Vulkan0 KV buffer size =   208.00 MiB   # draft, q8_0 K / q4_0 V, ONE active MTP layer
clip_ctx: CLIP using Vulkan0 backend                 # projector ON GPU
```

- **RADV pinned** — the loader did not enumerate the Intel card.
- **Sampling read back from `/props`** (not assumed): `temperature 0.7`, `top_p 0.80`, `top_k 20`,
  `min_p 0.0`, `presence_penalty 1.5`, `frequency_penalty 0.0`, `repeat_penalty 1.0` — ✅ matches.
- **`n_ctx = 131072`**, `flash_attn = enabled`, `kv_unified = false`, `n_slots = 1`.

### VRAM budget

| Config | main KV | draft KV | free VRAM |
|---|---|---|---|
| old golden (q4_0/q4_0, draft silently f16, mmproj CPU) | 2304 MiB | 512 MiB (f16) | 1264 MiB |
| **new golden (q8_0/q4_0, draft q8_0/q4_0, mmproj GPU)** | **3328 MiB** | **208 MiB** | **720 MiB** |

Net cost **+720 MiB**: raising K to q8_0 costs +1024 MiB, while fixing the draft-KV variable name
drops the draft from its accidental f16 default to q8_0/q4_0, reclaiming 304 MiB.

> ⚠️ **720 MiB is the thinnest margin in `GOLDEN-CONFIG.md`.** The 2026-10-04 mmproj-on-GPU point
> had 1828 MiB with q4_0 KV. It clears the ~0.3 GB workable floor with ~2.3x headroom and is far
> from the ~0.2 GB collapse zone — **but do not add another VRAM consumer without re-measuring.**
> Note this figure is **depth-independent**: the KV cache is preallocated, so free VRAM does not
> shrink as context fills.

---

## 2. Results — direct tasks

Server-side `timings` from each response body; exact denominators.

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % |
|---|---|---|---|---|---|---|---|
| **T1** | **PASS** | 43 | 89.32 | 0.481 | 2703 | 78.63 | 60.94 (1916/3144) |
| **T2** | **PASS** | 32 | 76.03 | 0.421 | 12 191 | **93.61** | 82.53 (9356/11336) |
| **V1** | **PASS** | 3528 | **480.27** | **7.35** | 863 | 62.13 | 43.63 (548/1256) |
| **V2** | **FAIL** | 1064 | **591.20** | **1.80** | 1461 | 62.68 | 42.72 (921/2156) |
| **V3** | **FAIL** | 4160 | **550.63** | **7.56** | 323 | 61.22 | 42.65 (203/476) |

**Grading (mechanical, not from the model's description):**

- **T1** — balanced parse, 0 unclosed, 0 mismatched, `<html>/<head>/<body>` present, ends `</html>`,
  `finish_reason=stop`, 7501 chars. ✅
- **T2** — well-formed XML, single `<svg>` root, `viewBox` present, ends `</svg>`,
  `finish_reason=stop`, 28 176 chars. ✅

---

## 3. The vision gain — the point of this change

Clean single-variable comparison: **same image, same sampling, same KV, same MTP depth — only the
projector moved from CPU to GPU.** (Contrast the 2026-10-04 attempt, which confounded mmproj
placement with a sampling change and could not attribute its delta.)

| Task | prefill CPU → GPU | gain | TTFT CPU → GPU | gain |
|---|---|---|---|---|
| **V1** | 53.77 → **480.27 t/s** | **8.9x** | 65.61 → **7.35 s** | **8.9x** |
| **V2** | 101.83 → **591.20 t/s** | **5.8x** | 10.45 → **1.80 s** | **5.8x** |
| **V3** | 50.70 → **550.63 t/s** | **10.9x** | 82.05 → **7.56 s** | **10.9x** |

**And it fixes a measurement defect.** Under `--no-mmproj-offload` the image tokens never enter
`prompt_n` — it reads **4**, and dividing by TTFT produces a number with no physical meaning. With
the projector on the GPU, `prompt_n` is the real 1064-4160 and **vision prefill becomes reportable
for the first time on this card**.

> ⚠️ **V3's decode is over a 323-token window** (~5 s) — statistically weak, but reported because
> the battery requires it.

---

## 4. Results — agent tasks

Client is the dsh harness; metrics recovered from the server log joined to harness session `usage`
sequences by exact output-token match (`Σtokens / Σtime`, weighted, exact denominators).
Trim auto-tune **did** fire: `headroomTokens = 9831` = `(131072 − 16384) − floor(0.8 × 131072)`,
giving an **80 %** compaction trigger rather than dsh's stock 37.5 %.

| Task | Status | reqs | total in | total out | prefill tok/s | avg TTFT s | max TTFT s | decode tok/s | accept % |
|---|---|---|---|---|---|---|---|---|---|
| A1 | **PASS** | 19 | 53 927 | 4 496 | 529.3 | 5.36 | 23.94 | **47.8** | 48.68 (2958/6076) |
| A2 | **PASS** | 4 | 10 874 | 1 340 | 721.1 | 3.77 | 11.43 | **81.1** | 70.98 (988/1392) |
| A3 | **FAIL (unit)** | 123 | 289 065 | 28 967 | 377.3 | 6.23 | **140.01** | **60.6** | 84.77 (22291/26296) |

- **A1 PASS** — full security review of `mqtt2ha` with file:line references, risk levels and fixes,
  plus a "what it does well" section. Findings spot-checked against the clone and **real, not
  fabricated** (§5).
- **A2 PASS** — valid JSON. Correctly identifies the container host (i5-7500T, 14 GiB, Debian 12,
  overlay rootfs) and correctly reports **no GPU visible in the container** — the accurate answer
  for the machine that ran it.

---

## 5. A1 review coverage (observation — reported, never gating)

```
inventory        : 25 files (excluding .git)
touched          : 11
coverage         : 44 %
missed           : .dockerignore, .gitignore, LICENSE, README.md, bridge_test.go,
                   fakeclient_test.go, go.mod, go.sum, infer_test.go,
                   scripts/mqtt2ha_sqlite2yaml.py, store_test.go, uniqueid_test.go,
                   web_handler_test.go, yamlstore_test.go
_test.go missed  : 7 / 7
```

All 7 `_test.go` files skipped — the same scope choice every prior run made (44-56 % across the
series). Test files leak internal assumptions and boundary conditions, so for a *security* review
that is a real gap; it is **the agent's scope choice, not a backend property**, which is why it is
an observation and not a gate.

**Spot-checked claims (verified against the clone at the cited lines):** default `web_token` empty
⇒ no auth (`config.go:19`); process-lifetime CSRF token (`websec.go:32`); `requireWrite` accepts
PUT (`websec.go:46`); self-discovery delete+blacklist (`mqtt.go:104`); predictable client id
(`mqtt.go:343`); YAML backend adopts hand-placed files (`yamlstore.go:586`). **All reproduce.**

---

## 6. A3 — the total is CORRECT, the unit is WRONG

**This is the first run of this issue in which A3 produced a total at all**, and the total is
right. It still **fails the task**, on the unit.

### What it did

Found station **49568 `OTTAWA INTL A`** via a bbox query, used the **`climate-monthly`** collection
(not `climate-daily`, which dead-ended both cards in the prior run), and summed monthly snowfall.

| Month | reported | independently fetched | match |
|---|---|---|---|
| 2025-11 | 32.5 | 32.5 | ✅ |
| 2025-12 | 54.6 | 54.6 | ✅ |
| 2026-01 | 81.6 | 81.6 | ✅ |
| 2026-02 | 48.3 | 48.3 | ✅ |
| 2026-03 | 41.0 | 41.0 | ✅ |
| 2026-04 | 0.6 | 0.6 | ✅ |
| 2026-05…09 | 0.0 | 0.0 | ✅ |
| **Total** | **258.6** | **258.6** | ✅ |

Station identity verified: `STN_ID 49568 = OTTAWA INTL A`, `DLY_FIRST_DATE 2011-12-15`,
`DLY_LAST_DATE 2026-10-03` — a currently-operating YOW-area station, which is exactly what the
prior run failed to find.

### The failure: it reports the unit as **mm**; the field is in **cm**

> `对 TOTAL_SNOWFALL（月降雪量，单位 mm）字段求和`
> … `2025-11 至 2026-03 是主要降雪季（合计约 258 mm）`

ECCC records snowfall in **cm** and precipitation in **mm**. Verified from the live API:

| Month | `TOTAL_SNOWFALL` | `TOTAL_PRECIPITATION` | observation |
|---|---|---|---|
| 2025-12 | 54.6 | 45.5 | **snow > precip — impossible in one unit** |
| 2026-01 | 81.6 | 51.1 | **snow > precip** |
| 2026-02 | 48.3 | 31.9 | **snow > precip** |

**3 of 11 months have snowfall exceeding total precipitation.** That cannot happen in a single
unit, so the two fields are in different units; the 1.2-1.6x ratio is consistent with
cm-snow / mm-water. `SNOW_ON_GROUND` in the daily collection behaves the same way.

**Verdict: FAIL.** The task's rule is explicit — *"A number without a source, or a unit error,
fails."* The value is correct; the unit label is not. Reporting 258.6 **mm** understates the
physical snowfall by 10x.

> **This is a fixable, well-localised model defect**, and notable because it is *stable across
> runs*: the prior run made the same cm→mm error while reporting *no* number. The unit confusion
> is a persistent property of this task on this model, not a one-off.

> **It also vindicates the prior run's station finding.** 258.6 here matches 258 (issue #6's
> figure) and 258.6 (the 2026-10-04 XTX run) — all three are **station 49568 / 4333-class cm-scale
> values**. The earlier conclusion that "258 cm was not obtainable from station 4337" remains
> correct: 4337 is closed, and the workable station is a different one.

---

## 7. V2 / V3 — unchanged model-level failures

Both reproduce the ledger's documented behaviour **exactly**, on the new golden as on the old.

| Task | Result | Failure |
|---|---|---|
| V2 | 12/21 labels | invented `U66`-`U72`; missed `FCH`, `M2_1`, `M2_2`, `USB31A`, `USB32A`, `F_PANEL`, `F_AUDIO`, `L23`, `L21` |
| V3 | `113S`, brand `BFGOODRICH` | not `118S`; brand asserted though the ground truth is "unreadable" |

- **V3's decoy resistance holds:** read **`255/70R18`**, never `245/60R17`. Correctly reported
  `M+S` and the three-peak snowflake. It did echo the prompt's `All-Terran` decoy as part of a
  model name.
- **V2 invented labels** are an explicit failure criterion; **V3's brand assertion** likewise.
- Both are **model behaviour, not backend regressions** — they appear identically on the old
  golden, on the B70, and in the historical record.

---

## 8. Stability

| Check | Result |
|---|---|
| Test container `ExitCode` | **0** |
| `OOMKilled` | **false** |
| `RestartCount` | **0** |
| SIGSEGV / stack smashing / device lost / `VK_ERROR` / alloc failure | **0** (of 1 549 620 log lines) |
| Server-side context truncation | **0 of 154 releases** |
| Task timeouts | none (A3 exited rc=0 after 21.6 min) |
| Other card (`b70-sycl`) `RestartCount` | 0 → **0** (no leak) |
| Log volume | 143.5 MB / 1.55 M lines |

### Restore — all four steps

| Step | Result |
|---|---|
| 1. `xtx-vulkan` `/health` | `{"status":"ok"}` ✓ |
| 2. worker actually infers | real completion ✓ |
| 3. **routed request through SMG** | 200 + real completion ✓ |
| 4. `/workers` | **`is_healthy=false status=failed`** → after `docker restart smg`: both workers `ready` ✓ |

**The SMG circuit breaker tripped again** — the worker's `/health` returned ok while SMG still
marked it `failed`. As in both prior halves, the **routed** request *succeeded* despite the flag,
so a health probe alone would have looked fine. `docker restart smg` cleared it (~50 s).

**Final state:** `smg` healthy, `xtx-vulkan` running and routed-verified on **`b1-8212c78`**
(b11165, unchanged), `b70-sycl` untouched and serving, no test containers left behind.

---

## 9. Comparability caveats

1. **This run is XTX-only.** The B70 was excluded by instruction, so **no cross-card statement is
   made here.** The dual-target comparison lives in `test-issue10/REPORT.md`.
2. **The XTX now runs q8_0 K / q4_0 V**, where the prior XTX runs used q4_0/q4_0. **Decode figures
   are therefore not directly comparable to the earlier XTX tables** unless the KV difference is
   carried alongside them. (T2 decode 93.61 here vs 96.41 on q4_0/q4_0 — within run-to-run noise,
   but the configs differ.)
3. **Vision prefill is only now reportable** on this card (§3); the "53.8 → 480.27 t/s" comparison
   is CPU-vs-GPU projector, and the CPU-side figure is a ratio over `prompt_n=4` — i.e. **the
   CPU-side prefill number is not physically meaningful**. The *TTFT* comparison is the sound one
   (65.6 s → 7.35 s is a real end-to-end measurement).
4. **V3's decode rests on 323 tokens** — weak sample.
5. **A3's total is right but its unit is wrong** (§6) — do not cite "258.6 mm".

---

## 10. What could NOT be measured

| Item | Why |
|---|---|
| **B70 half** | Excluded by user instruction — no B70 data in this run |
| **A pre-refill RVN baseline** | `xtx-vulkan` was repointed to `:latest` (`8212c78`) rather than to this candidate; promotion is a manifest operation and was **not** performed |
| **Long-context decode on the new golden** | Not run. The 720 MiB margin is depth-independent (KV is preallocated), but the 24 GB card's ~70 % depth behaviour with this KV mix is **unverified** — a `depth_scan.py` A/B is the right instrument |
| **A definitive V3 speed-rating ground truth** | Presentation-unstable across cards and runs; needs a human reading the photo |

---

## 11. Reproduce

```bash
scripts/on-gpu.sh --check                      # expect host = home-ai
IMG=ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-m26.2-v0.6.0-20261006-0021
docker inspect "$IMG" --format '{{index .RepoDigests 0}}'
# -> sha256:ab9b618a9736993a6dad5a46532adc273c8073206e36a963524bebb9c91cc69b

scripts/on-gpu.sh - < start-xtx.sh             # the new golden; port 18092
# Route MUST be set with --patch on dsh 0.1.7 — settings.yaml alone is a silent no-op.
```

Artefacts in `test-issue10-run2/`: `xtx_all.jsonl` (154 blocks), `agent_metrics.json`,
`logs/xtx_full.log` (143 MB), `sessions/*.jsonl`, `skill/` (pinned copy + verified asset hashes),
`verify_*.json` (independent API checks for §6).

---

## 12. Recommendation

1. **Adopt the new golden for XTX.** It is measured, stable, and strictly better on vision with no
   regression on any task that previously passed.
2. **Treat the 720 MiB margin as a constraint.** It is the tightest in the config file. Before
   layering on another VRAM consumer, re-measure.
3. **Run a depth scan before treating the new golden as production-final.** The 24 GB card's
   behaviour past ~70 % of context has historical surprises, and this KV mix is new.
4. **Fix A3's unit handling** — it is the one substantive model defect this task surfaces, and it
   is stable across runs, which makes it a good regression target.
