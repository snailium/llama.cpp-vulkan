# Muse-Glimmer-30B Test Report #3 — 7900 XTX (Vulkan) · **dynamic** build · everything on GPU

**Date:** 2026-10-16 · **Host:** home-ai `.101` · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB)
**Backend:** `llama-vulkan:v0.7.0` (commit `620d222`) · Vulkan / RADV, Mesa 26.2.3
**Harness:** dsh 0.2.0-rc.2 · **Skill sha256:** `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53`

**Config under test — as requested: dynamic weights, drafter AND mmproj fully in VRAM, KV f16.**
`n_ctx_slot=131072`, `--parallel 1`, `draft-dflash` (`n_max=3`), **481 MiB free after load**.

Artifacts from the official repo (`meta-models/Muse-Glimmer-30B-GGUF`); `dynamic` =
`Muse-Glimmer-30B-KQuant-Dynamic-Q4_K_XL.gguf`.

## Results — 6/8 PASS

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 html | **PASS** | 35 | — ᵀ | 1.870 | 1946 | 76.20 | 59.29 | balanced, ends `</html>` |
| T2 svg | **PASS** ‡ | 26 | — ᵀ | 2.173 | 1890 | 85.87 | 71.67 | well-formed, `viewBox`, ends `</svg>` |
| A1 security | **PASS** | — | 643.0 (agg) | — | 3569 (agg) | 52.30 (agg) | 35.49 | max single req 12845 tok |
| A2 hostinfo | **PASS** | — | 610.6 (agg) | — | 4714 (agg) | 75.70 (agg) | 63.54 | GPU PCI IDs correct, typed |
| A3 snowfall | **FAIL** | — | 611.1 (agg) | — | 4534 (agg) | 64.30 (agg) | 50.85 | **192.1 cm** — third distinct wrong answer |
| V1 game popup | **FAIL** | 4135 | 103.92 | 39.789 | 256 | 74.31 | n/a | **truncated**: answered only the debuff half |
| V2 motherboard | **PASS** | 1297 | 110.84 | 11.701 | 549 | 57.31 | n/a | **17/21 — best of any run** |
| V3 tyre | **PASS** | 4147 | 112.14 | 36.980 | 659 | 53.58 | n/a | size correct; **declined the rating entirely** |

ᵀ T1/T2 prefill is fixed overhead at 35/26 prompt tokens.
‡ **T2 was initially graded FAIL by my own grader, not by the model.** See "Grader bug" below.

## Grader bug — a false FAIL I caught before reporting it

T2 first failed with `XML parse error: line 1, column 0`. The cause was **my** `strip_fence`:

```python
re.match(r"\s*```[a-zA-Z0-9]*\s*\n(.*?)\n?\s*```\s*$", c, re.S)   # anchored to the whole string
```

It only matched when the code fence spanned the entire output. This run wrapped the SVG in a
fence **and** appended a sentence of prose after it, so the anchored regex returned the raw
text (fence + commentary) and every structural check failed on valid SVG. Verified: with the
fence extracted correctly, the output is well-formed, single `<svg>` root, `viewBox` present,
ends `</svg>` — **a real PASS**. The grader is now `re.search(...)` (unanchored).

The same bug would have hit T1. It is fixed in `run_muse_t1t2.py`; the copy that ran is
preserved at `runDYN/run_t1t2_fixed.py`.

## A3 — a third distinct wrong answer

| run | config | answer | method |
|---|---|---|---|
| #1 | q8_0 KV, no drafter, v0.6.0 | **258.0 cm** ✅ | real ECCC daily CSVs, summed |
| #2 | f16 KV + drafter, v0.7.0 | 302.2 cm ❌ | 1991-2020 climate normals |
| **#3** | **dynamic + drafter, f16 KV, v0.7.0** | **192.1 cm** ❌ | described the method, gave no summation |

Three runs, three different answers, and only the first did the task as written. A3 also
consumed only 12774 prompt tokens this time (vs 20579 in #2), so the shallower answer is not
a context-pressure artifact.

**A3 is not a usable task for this model on this backend.** It is not measuring the backend;
it is measuring the model's willingness to do a summation, which varies run to run.

## V3 — the safest behaviour yet

This run read the size correctly (`255/70R18`) and **declined to state the speed rating at
all** — no `11xS` appears, correct or incorrect. Across three runs:

| run | rating given | brand |
|---|---|---|
| #1 | declined ✅ | declined ✅ |
| #2 | `115S` ❌ | not asserted |
| **#3** | **declined** ✅ | not asserted |

The refusal behaviour reproduces, and the `115S` in #2 now looks like the outlier. Size and
both decoys were handled correctly in all three runs.

## V1 — a new failure: truncation

V1 answered **only the debuff half** of the popup (`减少5级防御力 / 防御力减少75% / 沉默`) and
never named the ultimate (`千律`), its damage (`850%` / `400%`), or the class (`XR2` — though
`莉拉` and `700` are present). `finish_reason=stop` with a 256-token completion, so the model
chose to stop early rather than being cut off.

Against the task's ground truth (name, level, and popup contents) this is **incomplete →
FAIL**. Worth noting the same task PASSED in runs #1 and #2.

## The 21.6k context crash — present, but not triggered

The pressure scan (see `2026-10-16-muse-glimmer-xtx-context-pressure.md`) established a
deterministic **SIGSEGV at ~21.6k prompt tokens** on this model + backend, independent of
build, drafter, or free VRAM. This run's maximum single-request prompt was **12845** (A1), so
it stayed clear. **The crash is real and reproducible; this battery simply did not reach it.**

A3's 20579-token request in run #2 remains the closest any real task has come (~95 % of the
boundary).

## VRAM: 481 MiB was sufficient for every task

| | |
|---|---|
| free after load | **481 MiB** |
| minimum free during the deepest request | not separately sampled in this run |
| OOMKilled / exit code | `false` / **0** — clean shutdown |
| crashes | **0** in 609 log lines |
| `b70-sycl` RestartCount | **0** → **0** |

**Everything fit and ran.** The dynamic build's thin headroom did not cause a failure in this
battery — including the 4135-token vision prompts and a 12845-token agent request.

## Performance

| | dynamic + drafter | 17gb + drafter (run #2) |
|---|---|---|
| decode, direct tasks | 76.2 / 85.9 | 75.9 / 95.1 |
| decode, agent aggregate | 52.3 / 75.7 / 64.3 | 56.9 / 84.8 / 71.9 |
| acceptance range | 35.5 – 71.7 % | 35.1 – 69.8 % |

Essentially identical. The extra 0.83 bpw of precision costs nothing measurable in speed, and
buys nothing measurable in speed either — consistent with the controlled 3×3 comparison in
the pressure report.

## Verdict

**The configuration works — 481 MiB free is enough for this whole battery — but the model's
task behaviour is unstable across runs, and that is the finding that matters.**

| | |
|---|---|
| Configuration | ✅ dynamic + drafter + mmproj on GPU, KV f16, 131072 ctx — all loaded, all served |
| Stability | ✅ 0 crashes, clean exit, no leakage to the other card |
| Failures | A3 (third distinct wrong answer) and V1 (truncated) — **both new or different from run #2** |
| Signal | **V2 improved to 17/21**, V3's safe refusal reproduced |

**Across three runs the same 8-task battery has produced 8/8, 6/8, 6/8 — and the specific
failures differ every time.** A3 has now failed in three different ways. That variance, not
the quant level and not the VRAM headroom, is what limits this model's usefulness as an agent
backend on our platform.

**Do not promote on the basis of this run.** It shows the *configuration* is viable; it does
not show the *model* is reliable.

## Honest boundaries

1. **n=1 per task.** With three runs of the same battery now on record and failures differing
   each time, the variance is the headline — but no single run is conclusive.
2. **The 21.6k crash was not exercised.** A3 in run #2 came within ~1000 tokens of it.
3. **V1's truncation may be a wording/threshold artifact** of a 256-token completion that
   stopped on its own; it is a FAIL against ground truth but not a capability statement.
4. **Dynamic vs 17gb quality is not established.** Meta reports 0.2 % vs 1.0 % degradation on
   15 benchmarks (a 0.8 pp difference) — far below the run-to-run variance measured here.
5. **The grader bug means report #1/#2 T1/T2 gradings should be re-checked** with the
   unanchored `strip_fence`; both runs passed, but the check was weaker than believed.

## Artifacts

`/models/muse-glimmer/runDYN/` on `.101`: T1/T2/V1-V3 outputs + results, `a{1,2,3}_*_run.log`,
`backend_logsDYN/`, `backend_full.log`, `run_t1t2_fixed.py`.
Related: [pressure scan report](2026-10-16-muse-glimmer-xtx-context-pressure.md) ·
[run #1](2026-10-13-muse-glimmer-30b-xtx-first-run.md) · [run #2](2026-10-16-muse-glimmer-30b-xtx-v070-f16kv-dflash.md).
