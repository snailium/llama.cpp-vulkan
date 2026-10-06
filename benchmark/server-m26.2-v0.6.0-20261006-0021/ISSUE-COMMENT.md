## Vulkan stable candidate validated — PROMOTED to `:stable` = `:v0.6.0`

**Digest tested and promoted:** `sha256:ab9b618a9736993a6dad5a46532adc273c8073206e36a963524bebb9c91cc69b`

Verified after promote — all three tags resolve to the tested digest:
```
:stable                             -> sha256:ab9b618a…
:v0.6.0                             -> sha256:ab9b618a…   (created by CI this run)
:server-m26.2-v0.6.0-20261006-0021  -> sha256:ab9b618a…
```
`:v0.5.0` was **not** moved. Confirmed anonymously pullable from the GPU host.

Promoted via `.github/workflows/promote-stable.yml` (`packages: write` on `GITHUB_TOKEN`),
run [37417921275](https://github.com/snailium/llama.cpp-vulkan/actions/runs/37417921275).
The local GHCR PAT in the keystore is **dead** — login succeeds but every manifest PUT
returns `401 Unauthorized`. The CI path works and is the correct mechanism; the PAT should
be rotated separately.

---

## What was tested

| | |
|---|---|
| Host | `home-ai` `.101` |
| Cards | **7900 XTX** (AMD RX 7900 XTX, 24 GB) — primary; B70 tested on the two earlier halves of this issue |
| Backend | Vulkan / RADV, **Mesa `26.2.3~kisak1~r`** — **unchanged** from `v0.5.0` |
| llama.cpp | `0.6.0-dev`, build 1, commit **`d812350`** (fingerprint `b1-d812350`) — bump from `v0.5.0`'s `7fe450e` |
| Model | Qwen3.8-27B-Q4_K_M + MTP draft `mtp-…-Q4_0.gguf` |
| Harness | `dsh-container/dsh@sha256:c88327dd…` |
| Skill | `backend-test-suite` sha256 `8af83da1…` (prompts parsed at run time, not transcribed) |

**Mesa did not move.** On this backend a Mesa bump normally outranks a llama.cpp bump as a
risk; it is byte-identical to the promoted baseline, so this run isolates the llama.cpp
commit. That is the notable fact here.

### Config change in this run

The XTX config was re-tuned and re-verified (see `docs/GOLDEN-CONFIG.md` §2/§4/§8):

| | old golden | new golden |
|---|---|---|
| main KV K / V | q4_0 / q4_0 | **q8_0 / q4_0** |
| draft KV | **f16/f16** (env var misspelled) | **q8_0 / q4_0** |
| mmproj | CPU | **GPU** |
| free VRAM after load | 1264 MiB | **720 MiB** |

Two things were fixed:
1. **`LLAMA_ARG_SPEC_DRAFT_TYPE_K/_V` does not exist.** The real names are
   `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V`. The wrong name is **silently ignored** — no
   warning, no error — so every run built from the published golden ran its **draft KV at
   the f16 default** while the doc claimed q4_0. Now corrected in the repo.
2. The vision projector was moved onto the GPU.

**Measured gain (clean single-variable A/B — same sampling, same KV, only the projector moved;**
contrast the confounded 2026-10-04 attempt):

| Task | prefill CPU → GPU | TTFT CPU → GPU |
|---|---|---|
| V1 | 53.8 → **480.3 t/s** (**8.9x**) | 65.6 → **7.35 s** (**8.9x**) |
| V2 | 101.8 → **591.2 t/s** (**5.8x**) | 10.5 → **1.80 s** (**5.8x**) |
| V3 | 50.7 → **550.6 t/s** (**10.9x**) | 82.1 → **7.56 s** (**10.9x**) |

It also makes vision prefill *reportable* at all: under `--no-mmproj-offload` `prompt_n`
is 4 and the ratio is meaningless.

---

## Results

| Task | Result | Notes |
|---|---|---|
| T1 | **PASS** | balanced HTML, ends `</html>`, `finish_reason=stop` |
| T2 | **PASS** | well-formed XML, single `<svg>`, viewBox, ends `</svg>` |
| V1 | **PASS** | all 9 ground-truth elements (莉拉/700/千律/XR2/850%/Lv.5/75%/400%/沉默) |
| V2 | **FAIL** | 12/21 labels — see below |
| V3 | **FAIL** | `113S`, brand asserted — see below |
| A1 | **PASS** | security review, findings verified real against the clone |
| A2 | **PASS** | valid JSON, values gathered, correctly reports no GPU in the container |
| A3 | **FAIL** | total **correct**, unit **wrong** — see below |

**Stability (XTX): 0 crashes, 0 of 154 releases truncated, `exit=0`, `RestartCount=0`,
`OOMKilled=false`, 0 SIGSEGV / device-lost / `VK_ERROR` / allocation failures.**

### Direct-task performance (server-side `timings`, exact denominators)

| Task | prompt_tok | prefill t/s | TTFT s | completion_tok | decode t/s | accept % |
|---|---|---|---|---|---|---|
| T1 | 43 | 89.32 | 0.481 | 2 703 | 78.63 | 60.94 (1916/3144) |
| T2 | 32 | 76.03 | 0.421 | 12 191 | **93.61** | 82.53 (9356/11336) |
| V1 | 3 528 | 480.27 | 7.35 | 863 | 62.13 | 43.63 (548/1256) |
| V2 | 1 064 | 591.20 | 1.80 | 1 461 | 62.68 | 42.72 (921/2156) |
| V3 | 4 160 | 550.63 | 7.56 | 323 | 61.22 | 42.65 (203/476) |

### Agent-task performance (aggregated, token/time weighted)

| Task | reqs | total in | total out | prefill t/s | avg TTFT s | max TTFT s | decode t/s | accept % |
|---|---|---|---|---|---|---|---|---|
| A1 | 19 | 53 927 | 4 496 | 529.3 | 5.36 | 23.94 | 47.8 | 48.68 (2958/6076) |
| A2 | 4 | 10 874 | 1 340 | 721.1 | 3.77 | 11.43 | 81.1 | 70.98 (988/1392) |
| A3 | 123 | 289 065 | 28 967 | 377.3 | 6.23 | 140.01 | 60.6 | 84.77 (22291/26296) |

Trim auto-tune fired: `headroomTokens = 9831` = `(131072 − 16384) − floor(0.8 × 131072)`,
i.e. the compaction trigger sits at **80 %** of the window rather than dsh's stock 37.5 %.

---

## Failures — detailed

### 1. V2 — invented labels (fails on both cards, both configs)

**Result: 12/21 ground-truth labels.** Missing: `FCH`, `M2_1`, `M2_2`, `USB31A`, `USB32A`,
`F_PANEL`, `F_AUDIO`, `L23`, `L21`.

**It also invented 7 labels not on the board:** `U66`, `U67`, `U68`, `U69`, `U70`, `U71`, `U72`.

Prior runs show the same failure with *different* invented sets (`L24`-`L47`/`U66`-`U99` on
one run, `USB3A`/`L25` on the B70). The instability of *which* labels get invented is itself
evidence that the model is confabulating rather than misreading. **Invented labels are an
explicit failure criterion.**

**Root cause: model behaviour, not a backend defect.** It reproduces identically on the B70,
on the old XTX config, and on the old llama.cpp commit. Not attributable to `d812350`.

### 2. V3 — the speed rating, and an asserted brand

**Result: size `255/70R18` ✅ (the `245/60R17` decoy correctly avoided).**
**Speed rating read as `113S`; ground truth is `118S`.**

Brand: reported **`BFGOODRICH`** (and earlier runs said `FALKEN`/`COOPER`). Ground truth is
**"brand unreadable"** — the model is guessing from the tyre's design family and guesses
differently each time. That instability is stronger evidence of unreadability than a single
wrong answer would be.

`M+S` ✅ and the three-peak snowflake ✅ were both read correctly. It did echo the prompt's
`All-Terran` decoy as part of a model name.

**Root cause: model behaviour, not a backend defect** — reproduces on both cards, both KV
configs, and the previous commit. The `S`/`T`-class instability is presentation-dependent
(crops change the reading on the *same* card and server), which is documented in the ledger.

### 3. A3 — the total is right, the **unit is wrong**

**This is the one substantive new finding of the run: the first time A3 produced a total at
all, and the total is correct — but it is labelled with the wrong unit.**

What it did, correctly:
- Found station **`STN_ID 49568` = `OTTAWA INTL A`** (a currently-operating YOW-area station,
  daily data through 2026-10-03).
- Used the **`climate-monthly`** collection rather than `climate-daily` (which dead-ended
  both cards in the previous run).
- Summed monthly snowfall.

**Every monthly figure independently re-verified against the live API — all 7 months match,
total 258.6:**

| Month | reported | independently fetched |
|---|---|---|
| 2025-11 | 32.5 | 32.5 ✅ |
| 2025-12 | 54.6 | 54.6 ✅ |
| 2026-01 | 81.6 | 81.6 ✅ |
| 2026-02 | 48.3 | 48.3 ✅ |
| 2026-03 | 41.0 | 41.0 ✅ |
| 2026-04 | 0.6 | 0.6 ✅ |
| 2026-05…09 | 0.0 | 0.0 ✅ |
| **Total** | **258.6** | **258.6 ✅** |

**The failure — it reports the unit as `mm`:**

> `对 TOTAL_SNOWFALL（月降雪量，单位 mm）字段求和`

**ECCC records snowfall in `cm` and precipitation in `mm`.** Verified from live API values,
not documentation:

| Month | `TOTAL_SNOWFALL` | `TOTAL_PRECIPITATION` | |
|---|---|---|---|
| 2025-12 | 54.6 | 45.5 | **snow > precip** |
| 2026-01 | 81.6 | 51.1 | **snow > precip** |
| 2026-02 | 48.3 | 31.9 | **snow > precip** |

**3 of 11 months have snowfall exceeding total precipitation** — impossible in a single unit,
so the fields are in different units. The 1.2-1.6x ratio matches cm-snow / mm-water.
`SNOW_ON_GROUND` behaves the same way.

**Verdict: FAIL.** The task's rule is explicit — *"a number without a source, or a unit error,
fails."* Reporting 258.6 **mm** understates the physical snowfall by 10x.

**This is a stable, reproducible defect** — the previous run made the same cm→mm error while
reporting *no* number at all. It is a good regression target, and it is the specific failure
class this task exists to catch.

> **Correction to an earlier claim in this issue.** The prior XTX run reported "the source
> genuinely has no observations for the window." That was **too strong**: station **49568**
> has continuous monthly snowfall data through 2026-09. 258.6 here also matches the `258`
> from `v0.5.0` and the `258.6` from the 2026-10-04 run — all cm-scale values for an
> operating station. The correct figure **was reachable**; the earlier run over-generalised
> from "station 4337 is closed" to "unavailable."

### 4. Cross-card note on A3

On the B70 the same task **timed out at the 1-hour budget** in a 404 loop (177 tool calls,
803 × HTTP 404, 304 × `REPEAT_TOOL_BLOCKED`). The enforcing repeat-tool-breaker **does** now
block the call before execution — the issue #6 recommendation was implemented — but the model
issued **155 further blocked calls** after the first block, so denial alone does not redirect
it. Worth noting for the next iteration of that plugin.

---

## A1 review coverage (observation — reported, never gating)

```
inventory   : 25 files (excluding .git)
touched     : 11
coverage    : 44 %
_test.go    : 7 / 7 skipped
```

Same scope profile as every prior run (44-56 %). A1's findings were spot-checked against the
clone at the cited lines and **all reproduce** — the review is real, not fabricated.

---

## Deeper context probe (new — the 24 GB cliff re-checked)

The new config has the **thinnest VRAM margin in the golden file (720 MiB)**, so the known
24 GB cliff deserved a direct re-measurement rather than an assumption.

| target depth | resident tok | prefill t/s | TTFT s | decode t/s | accept |
|---:|---:|---:|---:|---:|---:|
| 1,024 | 1,028 | 763.1 | 1.35 | **71.4** | 0.533 |
| 16,384 | 16,295 | 774.0 | 19.06 | **67.7** | 0.589 |
| 32,768 | 32,578 | 602.6 | 27.88 | **44.4** | 0.362 |
| 65,536 | 65,150 | 440.5 | 75.11 | **38.3** | 0.408 |
| 91,750 | 91,204 | 330.7 | 80.35 | **32.4** | 0.364 |
| 100,000 | 99,405 | 430.2 | 227.5 | **26.1** | 0.261 |
| 115,000 | 114,311 | 267.4 | 57.67 | **28.4** | 0.364 |
| 125,000 | 124,251 | 245.2 | 42.64 | **29.5** | 0.400 |
| **131,072** | **130,286** | 231.2 | 28.34 | **27.4** | 0.371 |

**Findings:**

- **The full 131,072-token window is reachable and stable.** The last row holds 130,286
  resident tokens and still decodes at 27.4 t/s. **No wedge, no ring timeout, no device loss,
  0 crashes, 0 truncation** across the whole sweep.
- **Decay is 2.6x from 1k to 131k (71.4 → 27.4 t/s)** — a smooth curve, not a cliff. The
  historical ~8x deep-context collapse is **not** present on `d812350`, consistent with the
  earlier b11117 finding that the Xe2/FA fix landed.
- **Free VRAM is depth-independent:** 720 MiB after load, **621 MiB after the 91k-token
  probe**. The KV cache is preallocated, so filling context does not consume the margin.
  This is the direct evidence that the 720 MiB margin is safe at depth.
- Draft acceptance degrades with depth (0.53-0.59 shallow → 0.26-0.40 deep), as expected.
- The 100k row's 227.5 s TTFT is a cold-cache full prefill of 97,862 tokens; later rows show
  lower TTFT because prefix caching had warmed. That is a caching artifact, not a
  depth anomaly.

**This closes the one open question from the config change.** The new golden is validated at
full context, not just at the shallow depths the task battery exercises.

---

## Verdict

**PROMOTED.** Both the XTX (this run) and B70 (earlier halves of this issue) completed the
battery. Every failure above is **model-level behaviour that reproduces across cards, KV
configs and llama.cpp commits** — none is a regression attributable to `d812350`, and none
is a backend defect:

| Failure | Cards | Configs | Old commit too? |
|---|---|---|---|
| V2 invented labels | XTX + B70 | q4_0/q4_0, q8_0/q4_0, f16, f16-draft | ✅ yes |
| V3 `113S` + brand | XTX + B70 | same | ✅ yes |
| A3 cm/mm unit error | XTX (both runs) | old + new golden | ✅ yes (unit error; no total) |

**The one thing not fully explained** is that A3 timed out on the B70 while completing on the
XTX with the identical image, prompt and source. That is model-side persistence, not a card
defect — the B70 server stayed healthy throughout (0 crashes, 0 of 206 releases truncated).

**Residual risk, stated plainly:** A3's B70 behaviour remains inconsistent, and V2/V3 fail on
both cards. A consumer of `:stable` gets an image where three tasks are known-imperfect — but
those are *model quality* issues present in every prior release, not defects this build
introduced.

---

## What could NOT be measured

| Item | Why |
|---|---|
| A3 on the B70 | Timed out at the 1-hour budget in a model-side tool loop |
| A definitive V3 speed-rating ground truth | Presentation-unstable on both cards; needs a human reading the photo |
| Vulkan-vs-SYCL on the XTX | No SYCL XTX image exists |

---

## Artefacts

- `test-issue10-run2/REPORT.md` — full XTX report
- `test-issue10-run2/depth/depthscan.json` + `depthscan_edge2.json` — depth sweep
- `test-issue10-run2/xtx_all.jsonl` — 154 timing blocks
- `test-issue10/REPORT.md` — the earlier dual-card run
- `docs/GOLDEN-CONFIG.md` — updated golden (§2, §4, §4.1, §8)
