# Vulkan Stable Validation — dual-target (B70 + 7900 XTX) · `server-m26.2-v0.7.0-20261015-2252`

Date: 2026-10-15/16 · Host: `home-ai` `.101` (tested via `scripts/on-gpu.sh` from control host `PC-DEV` `.90`)
Issue: [snailium/llama.cpp-vulkan#12](https://github.com/snailium/llama.cpp-vulkan/issues/12) · Channel: **stable** · Labels: stable, vulkan

| Moving part | Value |
|---|---|
| **Image under test** | `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-m26.2-v0.7.0-20261015-2252` |
| **Image digest** | `sha256:e4c6b1d0d867c215faf86e4319cc7d7fccd284868cec00c96fb6493e10d56e03` |
| **Harness digest** | `ghcr.io/snailium/dsh-container/dsh@sha256:8ae9360ede0369dcaf37c203e849500dd9b5b5e71c4193951817dcfc4746c521` (dsh `0.2.0-rc.2`, pulled fresh) |
| **Skill sha256** | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` (8 prompts parsed at run time, none transcribed) |
| **llama.cpp** | `0.7.0-dev` (build 1, commit `620d222`) |
| **Mesa** | `26.2.3~kisak1~r` — **unchanged from the baseline** |
| **Previous baseline** | `server-m26.2-v0.6.0-20261006-0021`, digest `sha256:ab9b618a9736…` |
| **Model** | `Qwen3.8-27B-Q4_K_M.gguf` · MTP draft `mtp-…-Q4_0.gguf` |
| **Test home** | brand-new per card (`<run>/xtx/dsh-home`, `<run>/b70/dsh-home`) — never reused |
| **Trim auto-tune** | ON for both cards; persisted `headroomTokens: 9831` = `(131072 − 16384) − floor(0.8 × 131072)`, i.e. trigger at **80 %** of the 131072 window |
| **Sampling** | read back from the running server via `/props` on **both** cards: `temp 0.7, top_p 0.80, top_k 20, min_p 0.0, presence 1.5, frequency 0.0, repeat 1.0`. Request fields sent: **thinking-off + `max_tokens` only** |
| **Mesa vs llama.cpp** | **No Mesa bump this cycle** — 26.2.3 both before and after. The only change is llama.cpp `v0.6.0 → 0.7.0-dev` |

## Verdict

**The stable gate FAILS.** On the stable channel **both cards must pass**, and **neither does**:

| Card | Gate result | Cause |
|---|---|---|
| **7900 XTX** | ❌ **FAIL** | T1 structural defect (unbalanced `<div>`); V2 invented labels; V3 wrong load index + fabricated brand |
| **B70 (Vulkan)** | ❌ **FAIL** | V2 invented labels; V3 wrong load index + fabricated brand; A3 unit error (`mm` for a `cm` field) |

**Do not promote.** The image is **stable and crash-free on both cards** — this is not a stability
regression — but it does not clear the stable channel's all-tasks bar. Every failure is a
**model-output / task-quality** failure, not a backend failure, and **every one of them reproduces
on the baseline `v0.6.0` image as well** (§5), so this build introduces **no new defect**.

A secondary observation that is arguably the more useful finding: **T1 passes on the B70 and fails
on the XTX on the same image and the same prompt** — the two cards disagree on a deterministic-looking
structural task (§3). That is worth stating plainly rather than averaging away.

---

## 1. What was tested, per card

Both cards were run **sequentially**, one at a time, with the other card's production container left
running and serving. Order: XTX first, then B70.

### 7900 XTX (Vulkan / RADV, Mesa 26.2.3)

ICD pinned `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json`; ctx **131072**, KV **q8_0/q4_0**,
draft KV `q8_0/q4_0`, `--spec-draft-n-max 4`, flash-attn `on`, projector on GPU (env unset).

### B70 (Vulkan / ANV, Mesa 26.2.3)

ICD pinned `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json`; ctx **131072**, KV **f16/f16**,
`--spec-draft-n-max 3`, flash-attn `auto`, projector on GPU (env unset), draft KV **not set**
(B70 golden carries no draft-KV values — observed f16 default).

Verified live, not assumed:

- **Offload / device pinning.** Both containers were bound to the intended card (`b70-dev-test`
  → `/sys/class/drm/card1` = `xe`; `xtx-dev-test` → card2 = `amdgpu`) and served real completions;
  a silently CPU-offloaded run would have shown an implausible decode rate instead.
- **Draft-KV env spelling.** The image exposes only `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V`; the
  wrong `…_TYPE_K` spelling **does not exist** in it (verified by `grep -aoE` on
  `/app/libllama-common.so.0`). The XTX launch used the correct name.
- **Free VRAM (XTX).** 23839 / 24560 MiB used → **720 MiB free**, exactly the golden's recorded value,
  stable at rest and at depth (KV is preallocated). Above the ~0.3 GB workable floor.

> ⚠️ The `common_fit_params: failed to fit params to free device memory` line appears in **both**
> cards' logs. It is the **documented false alarm** (golden §4), not an OOM — on the B70 it is
> expected because the pre-check uses mmproj's 848 MiB worst case against 248 MiB of real tensors.
> Neither container ever restarted or OOM-killed.

---

## 2. Results — 7900 XTX

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % (K) | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **FAIL** | 43 | 149.50 | 0.83 | 7370 | 88.32 | 72.86 % (K=4) | **HTML not balanced** — 111 `<div>` vs 112 `</div>` |
| T2 | PASS | 32 | 77.42 | 0.72 | 6312 | 95.37 | 82.07 % (K=4) | well-formed XML, single `<svg>` root, viewBox, ends `</svg>` |
| A1 | PASS | 42806 | 527.3 † | 7.57 avg | 3667 | 47.9 ‡ | N/A (no spec on the harness path) | real clone, file:line-cited review |
| A2 | PASS | 10723 | — § | 1.12 avg | 1267 | 79.5 ‡ | N/A | JSON valid; values gathered; GPUs real |
| A3 | **FAIL** | 371388 | 351.0 † | 6.56 avg | 17072 | 68.2 ‡ | N/A | correct unit (cm) but **headline total 298.4 ≠ its own table's 258.6** |
| V1 | PASS | 3528 | 481.64 | 6.9 ¶ | 666 | 72.36 | 55.70 % (K=4) | 莉拉 / LV700 / 千律 LV6 / XR2 / 850 % / Lv.5 −8 s / 400 % / 沉默 / −75 % |
| V2 | **FAIL** | 1064 | 558.93 | 1.90 ¶ | 1876 | 61.92 | 42.35 % (K=4) | **14/21** labels; **invented** `U530A`, `C061~C068`, `U47~U49`, `SATA`, `TP1`… |
| V3 | **FAIL** | 4160 | 261.29 | 7.38 ¶ | 262 | 64.57 | 47.78 % (K=4) | `255/70R18` ✅, M+S ✅, 3PMSF ✅, decoys resisted ✅ — but **`113S` ≠ 118S**, brand fabricated |

† prefill rate of the largest step (A1 17127 tok, A3 45447 tok).
‡ blended decode = Σoutput / Σgeneration-time over the session's steps.
§ A2's first step had no preceding timestamp, so no TTFT is derivable for it; the remaining steps average 1.12 s.
¶ vision TTFT is not emitted per-request by the client; prefill and decode come from `slot print_timing`, and TTFT = the measured `prompt eval time` (V1 7.325 s, V2 1.904 s, V3 15.921 s).

**KV precision caveat (mandatory).** The XTX runs **q8_0 K / q4_0 V**; a SYCL/golden comparison runs
**q8_0/q8_0**. These decode numbers are therefore **not a pure backend comparison** and must not be
read as one.

## 3. Results — B70 (Vulkan)

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % (K) | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 50.12 | 1.04 | 4689 | 51.66 | 82.41 % (K=3) | balanced, `<html>/<head>/<body>`, ends `</html>` |
| T2 | PASS | 32 | 43.95 | 1.07 | 4717 | 54.46 | 88.98 % (K=3) | well-formed XML, single `<svg>` root, viewBox |
| A1 | PASS | 55747 | 136.8 † | 39.02 avg | 3803 | 26.5 ‡ | N/A | real review, H/M/L risk levels + fixes |
| A2 | **FAIL** | 10896 | — § | 3.60 avg | 1495 | 48.9 ‡ | N/A | JSON valid and host facts right, but claims **`/dev/dri 不存在` / "GPU 未透传"** |
| A3 | **FAIL** | 177627 | 93.3 † | 33.01 avg | 7531 | 35.9 ‡ | N/A | correct number **258.6** but labelled **mm** for a **cm** field — unit error |
| V1 | PASS | 3528 | 211.97 | 16.64 ¶ | 751 | 42.34 | 62.21 % (K=3) | matches ground truth; correctly separated skill-level vs character level |
| V2 | **FAIL** | 1064 | 281.20 | 3.78 ¶ | 2060 | 40.21 | 56.19 % (K=3) | **15/21** labels; **invented** `C04A`, `L20`, `L24–L30`, `U10`, `U11`… |
| V3 | **FAIL** | 4160 | 160.75 | 25.88 ¶ | 430 | 39.62 | 56.04 % (K=3) | `255/70R18` ✅, decoys resisted ✅ — but **`113S` ≠ 118S**, brand fabricated |

**T1/T2 cross-card disagreement.** T1 **passes on the B70** (4692 tokens, balanced) and **fails on the
XTX** (7370 tokens, one extra `</div>`). Same image, same prompt, same sampling. The XTX generated ~57 %
more text and over-closed a container `<div>`; the extra length is what surfaced the defect. T1 is a
sampling-sensitive structural task, not a backend property — reported as such.

**XTX vs B70 (V1-V3 prefill).** The B70's vision prefill is **2.3x slower on V1** (211.97 vs 481.64 t/s),
**2.0x slower on V2**, **1.6x slower on V3**, and its decode is consistently lower. This matches the
existing B70-on-Vulkan caution in the golden (§6) and is **not** attributable to this build.

**A2 cross-card disagreement (and why the B70 fails).** The XTX's A2 correctly detected both GPUs from
`/sys/class/drm/*/device/uevent` (`8086:E223`, `1002:744C`) — that data **is** visible inside the harness
container. The B70's A2 asserted `dri_devices: none (/dev/dri 不存在)` and `"gpu": {"detected": false}`,
which is **factually wrong for the container it ran in**. Since A2 is graded against **the machine that ran
the container**, the B70 answered incorrectly.

---

## 4. Stability

| | 7900 XTX | B70 |
|---|---|---|
| `RestartCount` | **0** | **0** |
| `OOMKilled` | **false** | **false** |
| Exit code | 0 | 0 |
| SIGSEGV / abort / device-lost | **none** | **none** |
| `failed to allocate` / alloc failure | none | none |
| kernel GPU events (`amdgpu` timeout/reset/wedge, `xe` error/hang) | **none** | **none** |
| Log lines / timing blocks carrying draft acceptance | 2343 / 214 | 1368 / 99 |

The only line matching a crash keyword on either card is the documented `common_fit_params` **false
alarm**; it is present on the unmodified golden configuration and is not a run finding.

**Card exclusivity held.** The other card's production container was baselined at `RestartCount=0`
before each run and re-checked after — it stayed **0** in both directions, so neither run leaked onto
the sister card. This was verified in both orders (XTX running during the B70 run and vice versa).

**No wedge.** A3 on the XTX drove a **45,447-token** prefill (35 % of ctx) with prefill decaying
smoothly to 351 t/s. This is well below the ~287 K / 80 %-of-131072 wedge zone documented in
`xtx-backend-test`, and no ring timeout occurred — so this run neither confirms nor contradicts that
boundary, and no coredump was produced.

## 5. Are these failures new? — No

Each failure reproduces on the **previous baseline image**, so none is a `v0.7.0` regression:

| Failure | Baseline `v0.6.0` (`server-m26.2-v0.6.0-20261006-0021`) | This run |
|---|---|---|
| V3 load index misread | XTX `113S`, B70 `T103S` — both ≠ `118S` | XTX `113S`, B70 `113S` — both ≠ `118S` |
| V2 invented labels | failed (invented labels) | failed (invented labels) |
| A3 unit error on B70 | recorded as a 10× unit error on the stable predecessor | `258.6 mm` for a cm field |
| T1 on XTX | n/a (prior run's T1 passed) | fails on unbalanced `<div>` |

The V3 defect in particular has now been observed on **three separate images** (`v0.4.1`, `v0.6.0`,
`0.7.0-dev`) and **both cards**, which makes it a **model/task-quality** property of
`Qwen3.8-27B-Q4_K_M` on this image family, not a backend regression.

> **On A3 specifically** — the ECCC `TOTAL_SNOWFALL` field is in **centimetres**, while
> `TOTAL_PRECIPITATION` is in **millimetres**. Verified directly against the live API for this window
> (station 49568): 2025-12 has `TOTAL_SNOWFALL = 54.6` but `TOTAL_PRECIPITATION = 45.5` — snowfall
> exceeding total precipitation is only possible if the units differ. The correct 6-month total is
> **258.6 cm**. The XTX's own monthly table sums to 258.6 (its 298.4 headline is an arithmetic slip);
> the B70 reports 258.6 but calls it **mm**. Both therefore misdeliver the figure.

## 6. Restoring production (both cards)

Each card was restored and verified **in order**, including the router step that is usually missed:

1. `/health` on the worker → `ok`
2. a real completion on the worker → `ok`
3. **a real completion through SMG** (`:40114`, with `X-SMG-Routing-Key`) → `ok`
4. `/workers` view

**Step 3 exposed a real platform-side issue, twice.** After each restore the worker answered `/health`
and inference fine, but SMG still listed it `is_healthy=False status=failed` — routed requests kept
working only because the *other* worker absorbed them. `docker restart smg` cleared it both times
(~40 s for workers to re-register). Final state:

```
http://192.168.111.101:18080   healthy=True  status=ready
http://192.168.111.101:18090   healthy=True  status=ready
router end-to-end: content "ok", finish_reason "stop"
xtx-vulkan  Up (healthy)  RestartCount=0  OOMKilled=false
b70-sycl    Up (healthy)  RestartCount=0  OOMKilled=false
```

Both test containers (`xtx-dev-test`, `b70-dev-test`) were removed; neither was left registered.

## 7. A1 review-coverage observation (reported, never gating)

| card | read calls | files touched / inventory | missed |
|---|---|---|---|
| XTX | 11 | **11 / 27 (41 %)** | `.dockerignore`, `.github/workflows/*`, `.gitignore`, LICENSE, README.md, go.mod, go.sum, `scripts/mqtt2ha_sqlite2yaml.py`, and **all 7 `_test.go`** |
| B70 | 9 | **9 / 27 (33 %)** | as above, plus Dockerfile and `config.example.yaml` |

Both cards skipped **every `_test.go` file** — the same gap recorded in the skill's own measured run
(44 %). For a *security* review that is a real gap, but it is the agent's scope choice, not a backend
property, and it is **not** scored.

---

## Verdict (restated)

**Do not promote `sha256:e4c6b1d0d867c215faf86e4319cc7d7fccd284868cec00c96fb6493e10d56e03` to `:stable`.**

- The stable gate requires **both cards to pass**; **neither does** (XTX 5/8, B70 5/8).
- The failures are **not stability failures** and **not regressions** — the image is crash-free on both
  cards and behaves at least as well as its predecessor. They are **task-quality** failures that also
  affect the current stable image.
- **Not shipping is the correct outcome here**, and it should be recorded as such.

**What would change this verdict.** A build whose V2/V3 model behaviour is unchanged will keep failing
these two tasks regardless of backend, so re-running the same gate on a backend-only rebuild is unlikely
to flip it. Either (a) the task definitions for V2/V3/A3 need revisiting — V3's ground truth includes an
unreadable brand that models reliably hallucinate, and A3's unit trap has now caught three consecutive
images — or (b) the stable gate needs to distinguish **backend regressions** (which this build does not
have) from **known model-quality defects** (which it inherits). That is a policy call for the repository
owner, not something to resolve by promoting.

---

### Provenance

- Run dir: `.tmp/vulkan-m26.2-v0.7.0-20261015-232649/` (`xtx/`, `b70/` result sets, decompressed sessions, full container logs)
- Prompts read from the skill file at run time (`skill/prompt_source.py`); skill sha256 pinned above.
- Both cards' sampling verified via `/props` **after** launch — not read from the launch intent.
