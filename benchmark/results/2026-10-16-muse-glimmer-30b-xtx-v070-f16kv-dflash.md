# Muse-Glimmer-30B Test Report #2 — 7900 XTX (Vulkan) · v0.7.0 · f16 KV · DFlash active

**Date:** 2026-10-16 · **Host:** home-ai `.101` · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB, NAVI31 / RDNA3)
**Backend:** `llama-vulkan:v0.7.0` = `sha256:` v0.7.0 (commit `620d222`) · Vulkan / RADV, Mesa 26.2.3
**Harness:** `dsh@sha256:8ae9360ede0369dcaf37c203e849500dd9b5b5e71c4193951817dcfc4746c521` (dsh 0.2.0-rc.2)
**Skill sha256:** `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53`

This is the run that supersedes #1: it uses the **newer v0.7.0 image**, **f16 K and V cache**,
and the **DFlash drafter — confirmed active**, which report #1 did not have.

## Weights — official Meta repo (sourcing precedence step 1)

| File | Size | sha256 (16) |
|---|---|---|
| `Muse-Glimmer-30B-KQuant-17GB-Q4_K_M.gguf` | 15.61 GiB | `4cc57c0f51040a22` |
| `mmproj-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.30 GiB | `f48b452316f9b213` |
| `dflash-Muse-Glimmer-30B-Q4_K_M.gguf` | 1.52 GiB | — |

All three from [`meta-models/Muse-Glimmer-30B-GGUF`](https://huggingface.co/meta-models/Muse-Glimmer-30B-GGUF).

## Configuration

| Knob | Value |
|---|---|
| ctx | **131072** (`n_ctx_slot` = 131072, not capped) |
| KV | **f16 / f16** |
| drafter KV | f16 / f16 |
| `--parallel` | 1 |
| spec | `draft-dflash`, `n_max=3` (llama.cpp default — Meta publishes no recommendation) |
| sampling | temp 1.0 / top_p 0.95 / top_k 64 (read back from `/props`) |
| free VRAM after load | **3172 MiB** (three consecutive reads, no drift) |

### Drafter activation — verified, not assumed

Startup log:

```
loading draft model '/models/muse-glimmer/dflash-Muse-Glimmer-30B-Q4_K_M.gguf'
adding speculative implementation 'draft-dflash'
- n_max=3, n_min=0, p_min=0.00
- block_size=16, mask_token_id=201818, n_extract=5, sample_from_anchor=true
```

Per-request: `draft acceptance = 0.83333 (175 accepted / 210 generated)`.

**`n_max=3` is llama.cpp's own default.** An earlier draft of the config proposed `n_max=2`
on the strength of B70/SYCL measurements with a *different* model and drafter; that was
discarded as non-transferable. Meta gives no guidance, so the default stands.

## Results Summary

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 html | **PASS** | 35 | — ᵀ | 1.355 | 1536 | 75.94 | **48.27** | balanced, ends `</html>` |
| T2 svg | **PASS** | 26 | — ᵀ | 1.577 | 1270 | 95.12 | **69.84** | well-formed, `viewBox`, ends `</svg>` |
| A1 security | **PASS** | — | 638.3 (agg) | — | 3576 (agg) | 56.90 (agg) | **35.07** | cites config.go, websec.go, store.go, mqtt.go |
| A2 hostinfo | **PASS** | — | 584.3 (agg) | — | 3937 (agg) | 84.80 (agg) | **64.18** | PCI IDs correct, devices typed not named |
| A3 snowfall | **FAIL** | — | 646.0 (agg) | — | 2663 (agg) | 71.90 (agg) | 51.93 | **answered 302.2 cm from climate normals — did not fetch daily data** |
| V1 game popup | **PASS** | 4135 | 294.47 | 14.042 | 441 | 73.23 | n/a ᴰ | every ground-truth element present |
| V2 motherboard | **PASS** | 1297 | 295.37 | 4.391 | 671 | 63.71 | n/a ᴰ | 15/21 labels |
| V3 tyre | **FAIL** | 4147 | 181.16 | 22.892 | 675 | 59.10 | n/a ᴰ | read **`115S`** — neither the truth (`118S`) nor the decoy |

ᵀ T1/T2 prefill is meaningless at 35/26 prompt tokens — TTFT is fixed overhead.
ᴰ Vision requests are single-shot, so per-request accept was not captured; the drafter was
confirmed active on the same server via the checks above.

A-task figures are aggregates over all completed requests (exact denominators).

## Decode: drafter gain

Same server, same config, prompt-dependent:

| Measurement | decode t/s |
|---|---|
| no draft (report #1, q8_0 KV, v0.6.0) | ~42 (flat across 8 tasks) |
| **with draft (this run)** | **56.9 – 95.1** |

Acceptance ranges **35 % (A1) to 70 % (T2)**. A1 is the low end and is also the task with
the longest tool-call chains, which is where draft propositions are least predictable.

**The gain is not uniform, and the low-acceptance case (A1, 35 %) is worth flagging**: a
drafter that accepts only a third of proposals still had to *propose* them, so the net win
there is small. No regression was observed, but the margin is thin on that task shape.

## Two failures — and one is a regression against report #1

### A3 — FAIL, and it failed differently from last time

Report #1: **258.0 cm**, from **real ECCC daily data** (CSVs downloaded into the workspace),
cross-checked against two season summaries.

This run: **302.2 cm**, computed from **1991-2020 climate normals** — an *expected value*,
not the measured total. It never downloaded the daily data.

Verified from the session: this run used `web_search_pro`/`web_fetch_pro` (5/3 calls) but
produced **no CSV files** in the workspace, whereas report #1's run left
`climate_daily_ON_6106001_2025_P1D.csv` and `_2026_P1D.csv`. So it searched, found normals,
and answered from those instead of doing the summation the task asks for.

It did **label** its answer as a climatological estimate rather than measured — which is
honest — but the task asks for the total and the method, and a normals-based expectation is
not the total. **FAIL.**

**This is a regression relative to report #1 on the same model.** The only config
differences are the image (v0.6.0 → v0.7.0), KV precision (q8_0 → f16), and the drafter
being on. Whether the drafter degraded this task is the obvious hypothesis, but n=1 on each
side cannot establish it.

### V3 — FAIL, and the failure mode moved

| run | size | speed rating | brand |
|---|---|---|---|
| report #1 | `255/70R18` ✅ | declined to read it ✅ | declined ✅ |
| **this run** | `255/70R18` ✅ | **`115S`** ❌ | truncated, not asserted |
| Qwen (all configs) | `255/70R18` | `113S` ❌ | asserted ❌ |
| **truth** | `255/70R18` | **`118S`** | unreadable |

So this run produced a *third* distinct wrong value (`115S`), where report #1 correctly
declined. Both the trap and the size were still handled correctly — it did not echo
`245/60R17` or `104T` — but the safe behaviour ("I cannot read it") did not reproduce.

**Together with A3, the pattern is that report #1's careful behaviour did not reproduce
under the new config.** That is the headline finding of this run, and it is not a
speed result.

### Everything else held

- **A1 PASS** — cites `config.go`, `websec.go`, `store.go`, `mqtt.go`, `discovery.go`; same
  grounding as report #1 (which was spot-checked against source).
- **A2 PASS** — identical GPU handling to report #1: correct PCI IDs (`8086:E223`,
  `1002:744C`) and devices typed (`Intel Arc / Xe based`, `AMD`) rather than misnamed.
  This is where Qwen reports "RX 7800 XT" and "UHD Graphics 770".
- **V1 PASS** — 莉拉 / 700 / XR2 / 千律 / 850 % / 400 % / 沉默 / 75 % all present.
- **V2 PASS** — 15/21, same set as report #1 and the same set Qwen finds, but without Qwen's
  ~70 invented labels.

## Stability

| check | result |
|---|---|
| `b70-sycl` RestartCount | baseline **0** → after **0** |
| OOMKilled / crashes | `false` / **0** in 560 log lines |
| production restore | worker healthy; SMG worker first showed `failed`, cleared by the documented `docker restart smg`, then **both workers `ready`** and a routed request returned `ok` (`b1-d812350`) |

**Operational note:** the harness profile's `baseURL` was pinned to the *previous* test
container's port (18093). Every request failed with `dsh: TRANSPORT: Connection error` until
the profile patch was repointed at the new port (18097). The profile persists the URL, so
**each new backend port requires updating the profile**, not just the container.

## Verdict

**The config works and the drafter delivers a real gain — but two behaviours that passed in
report #1 failed here, so this run does not support promotion on quality grounds.**

| | |
|---|---|
| Performance | decode **56.9–95.1 t/s** with draft vs ~42 without; acceptance 35–70 % |
| VRAM | **3172 MiB** free at 131072 with f16 KV and the drafter — comfortable |
| Correctness | **6/8 PASS** (was 8/8 in report #1) |
| Regression | A3 (answer quality/method) and V3 (safe refusal did not reproduce) |

**Do not promote on the strength of the speed gain alone.** The two failures are the kind
that matter for an agent backend, and the fact that they failed *differently* from the
previous run means at least one of them is variance, not a stable property — which is
itself a reason to repeat before concluding either way.

**What would resolve it:** repeat A3 and V3 several times under this config, and under the
report #1 config, to separate "the drafter/CPU-KV changed this" from "this model is
high-variance on these two tasks". A third config (f16 KV without the drafter) would isolate
the drafter specifically.

## Honest boundaries

1. **n=1 per task.** Both failures are single samples. A3's history in this project includes
   a documented 10× unit error on one of two runs of the *same* digest — this model task is
   known to be high-variance.
2. **Two config variables changed at once** (image version + KV precision + drafter) relative
   to report #1, so no failure can be attributed to the drafter specifically.
3. **No `n_max` sweep.** `n_max=3` is the default, untested against alternatives.
4. **Vision accept rates not captured** (single-shot requests).
5. **The drafter's memory was not measured during fitting** — the log shows
   `failed to measure the memory of the extra model, fitting without it`, which Meta's README
   calls harmless. The 3172 MiB figure is a post-load measurement, so it is unaffected, but
   the pre-load fit estimate does not account for the drafter.

## Artifacts

`/models/muse-glimmer/run16k/` on `.101`: T1/T2/V1-V3 outputs + result JSON, `a{1,2,3}_*_run.log`,
`backend_logs16k/`, `backend_full.log`, `run_metadata.json`.
Report #1: [`2026-10-13-muse-glimmer-30b-xtx-first-run.md`](2026-10-13-muse-glimmer-30b-xtx-first-run.md).
