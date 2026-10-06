# `server-m26.2-v0.6.0-20261006-0021` — validation archive

**Promoted to `:stable` = `:v0.6.0`** on 2026-10-06.

| | |
|---|---|
| **Image digest (tested = promoted)** | `sha256:ab9b618a9736993a6dad5a46532adc273c8073206e36a963524bebb9c91cc69b` |
| llama.cpp | `0.6.0-dev`, build 1, commit `d812350` (fingerprint `b1-d812350`) |
| Mesa | `26.2.3~kisak1~r` — **unchanged** from the `v0.5.0` baseline |
| Harness digest | `ghcr.io/snailium/dsh-container/dsh@sha256:c88327dd3686fa75b0195481a7a045e2f899345b8c79f54a6b23a8d57ddf29e5` |
| Skill sha256 | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Issue | [snailium/llama.cpp-vulkan#10](https://github.com/snailium/llama.cpp-vulkan/issues/10) |
| Promote run | [actions/runs/37417921275](https://github.com/snailium/llama.cpp-vulkan/actions/runs/37417921275) |

The digest above is the durable identity. Tags move; this directory does not.

## Contents

| File | What it is |
|---|---|
| `REPORT.md` | Full XTX report — results, failures, stability, comparability caveats |
| `ISSUE-COMMENT.md` | The comment posted to issue #10 (includes the B70 half's findings) |
| `xtx-timings.jsonl` | 154 server-side `timings` blocks, one per line |
| `agent-metrics.json` | Aggregated A1-A3 metrics (token/time weighted) |
| `depth/depthscan.json`, `depth/depthscan_edge2.json` | Deep-context sweep to the full 131,072 window |
| `t1_output.txt`, `t2_output.txt` | T1/T2 generation output, code fence stripped |
| `sessions/*.jsonl.zstd` | A1-A3 harness sessions, byte-exact as dsh wrote them |
| `sessions/*.jsonl` | The same, decompressed for reading without tooling |

## Configuration tested

The XTX golden was **re-tuned in this run** (see `docs/GOLDEN-CONFIG.md` §2/§4/§8):

| | old golden | new golden |
|---|---|---|
| main KV K / V | q4_0 / q4_0 | **q8_0 / q4_0** |
| draft KV | **f16/f16** (env var was misspelled) | **q8_0 / q4_0** |
| mmproj | CPU | **GPU** |
| free VRAM after load | 1264 MiB | **720 MiB** |

The draft-KV change is a **bug fix**, not a tuning choice: `LLAMA_ARG_SPEC_DRAFT_TYPE_K/_V`
does not exist upstream, is silently ignored, and left the draft KV at its f16 default. The
real names are `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K/_V`.

## Summary of results

| Task | XTX | B70 |
|---|---|---|
| T1 | PASS | PASS |
| T2 | PASS | PASS |
| V1 | PASS | PASS |
| V2 | FAIL | FAIL |
| V3 | FAIL | FAIL |
| A1 | PASS | PASS |
| A2 | PASS | PASS |
| A3 | FAIL (unit error) | TIMEOUT |

**Zero crashes and zero server-side truncation on both cards.**

All three failures are **model-level behaviour that reproduces across cards, KV configs and
the previous llama.cpp commit** — none is a regression attributable to `d812350`.

## Deep-context probe

The full 131,072-token window was reached and held (`130,286` resident tokens, 27.4 t/s).
Decode decays smoothly 71.4 → 27.4 t/s (2.6x) with **no wedge, no ring timeout, no device
loss**. Free VRAM is depth-independent: 720 MiB after load, 621 MiB after a 91k-token probe —
which is the direct evidence that the new config's thin VRAM margin is safe at depth.

## How to reproduce

```bash
scripts/on-gpu.sh --check                 # expect host = home-ai
docker pull ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:v0.6.0
# XTX config: docs/GOLDEN-CONFIG.md §4; launch with -lv 5 or the device/offload lines
#   never appear, and a grep for "offloaded" will wrongly suggest CPU execution.
```
