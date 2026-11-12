# llama.cpp Vulkan — standard backend battery · RX 7900 XTX · dev `server-dev-m26.2-b12182-20261107-0518`

**Date:** 2026-11-12 · **Host:** home-ai `.101` · **Card:** AMD Radeon RX 7900 XTX (24 GB / 24560 MiB, NAVI31, RADV)

| | |
|---|---|
| Backend image | `ghcr.io/snailium/llama.cpp-vulkan/llama-vulkan:server-dev-m26.2-b12182-20261107-0518` |
| Image digest | `sha256:e7c736f03b39fba4af3b5598057c315112e663176ca8366bd9f00d5ba5423488` |
| llama.cpp ref | **b12182** |
| Harness | `ghcr.io/snailium/dsh-container/dsh@sha256:89c689fb94072be46585b9d905215c19864ea079ac52551ca1de1107c0318acd` (dsh **0.2.2-rc.1**) |
| Skill sha256 | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Model | `/models/Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-…-Q8_0` (projector on GPU) |
| KV | **q8_0 K / q4_0 V** @ ctx 131072 · draft KV q8_0/q4_0 |
| Spec decode | `draft-mtp`, **K = 4** (`--spec-draft-n-max 4 --spec-draft-p-min 0.1`) |
| Free VRAM after load | **716 MiB** (used 23839 / 24560 MiB) |
| Sampling | **inherited** — read back from `/props`: temp 0.7, top_p 0.80, top_k 20, min_p 0.0, presence 1.5, frequency 0.0, repeat 1.0 (equals the golden) |
| Request fields sent | only `chat_template_kwargs:{enable_thinking:false}` and `max_tokens:32768` (T1/T2/V1-V3), plus `stream:true` for T1/T2 |
| Trim auto-tune | **ON** — `Retuned compaction-basic (…)`; persisted `headroomTokens=9831` = (131072−16384) − floor(0.8×131072) |

Prompts and the three vision images were read from the skill at run time (`assets/prompt_source.py`), not transcribed.

## Results Summary

| Task | Status | prompt_tok | prefill tok/s | TTFT s | completion_tok | decode tok/s | accept % | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | **PASS** | 43 | 177.1 | 0.454 | 4,321 | **98.72** | **84.64** | parses, html/head/body, ends `</html>`, finish=stop |
| T2 | **PASS** | 32 | 83.7 | 0.548 | 4,309 | **96.15** | **81.63** | well-formed XML, single `<svg>`, `viewBox`, ends `</svg>` |
| A1 | **PASS** | 41,750 ᵀ | 465.5 ᴹ | 2.406 ᴹ (max 23.3) | 3,550 | 47.97 ᴬ | 68.5 ᴬ | 12 findings (2 high / 5 med / 5 low), spot-checked against the clone |
| A2 | **PASS** | 8,363 ᵀ | 368.3 ᴹ | 1.500 ᴹ (max 10.2) | 1,341 | 86.40 ᴬ | 68.5 ᴬ | values gathered via 3 `bash` calls; GPU correctly reported absent in-container |
| A3 | **FAIL** | 189,175 ᵀ | 331.6 ᴹ | 0.976 ᴹ (max 74.1) | 11,193 | 76.18 ᴬ | 68.5 ᴬ | answered 194.0 cm; **the data it downloaded are 404 HTML pages** |
| V1 | **PASS*** | 3,528 | 487.8 | 7.232 | 936 | 72.30 | 57.89 | all ground-truth fields correct; **invented extras** — see below |
| V2 | **PASS** | 1,064 | 581.8 | 1.829 | 2,623 | 68.40 | 51.13 | **15/21** labels; also enumerated ~197 additional designators |
| V3 | **FAIL** | 4,160 | 264.8 | 15.707 | 415 | 64.20 | 48.06 | read **113S** (truth **118S**) and asserted a brand that is unreadable |

ᵀ Σ input tokens over all model steps · ᴹ median over steps (agent tasks make many requests) · ᴬ aggregate: output tokens ÷ Σ streamed step time, from the harness session.
Acceptance for A1-A3 is **weighted over all 129 requests in the server log** (22,955 accepted / 33,532 generated = 68.46 %), because the harness client never sees it.
All rows carry draft acceptance; K=4 throughout.

**6 / 8 PASS.**

## A1 — PASS, and the findings are real

2 high, 5 medium, 5 low, each with risk level, reason and a priority-ordered fix list. Spot-checked against the clone the agent made, not taken on trust:

| claimed | verified in source |
|---|---|
| H1: Web UI defaults to `:8080` on all interfaces | `config.go:46` → `HTTP: ":8080"` ✓ |
| M2: auth-failure throttle keyed on `RemoteAddr`, bypassable behind NAT/proxy | `websec.go:180` → `net.SplitHostPort(r.RemoteAddr)` ✓ |

The numbers it cites are consistent with the files it read. Not fabricated.

**A1 review coverage (observation — reported, never gating):**

```
files touched / inventory : 12 / 25  (48 %)
read calls               : 11
missed                   : .dockerignore, .gitignore, LICENSE, README.md, bridge_test.go,
                           fakeclient_test.go, go.sum, infer_test.go,
                           scripts/mqtt2ha_sqlite2yaml.py, store_test.go, uniqueid_test.go,
                           web_handler_test.go, yamlstore_test.go
notable                  : all 7 _test.go files skipped again — third run in a row with this
                           exact gap (11/25 = 44 % on 2026-09-27). Scope choice, not scored.
```

## A2 — PASS

Valid JSON; values gathered (`bash` ×3) and they match **the machine that ran the container** (`.101`), not the backend host by assumption: Ryzen 7 5700X (8c/16t), 60 GiB total / ~25 GiB available, 8 GiB swap, NVMe 465.8 + 476.9 GB, Debian 12 container on kernel `7.0.0-42-generic`, and **GPU: `detected: false`, stated as "no /dev/dri in this container"** — which is the correct answer, because the harness was not given the device.

## A3 — FAIL, and this one is evidence-based rather than a judgement call

It reported **194.0 cm** with a month-by-month table (Nov 2025 – Mar 2026), citing ECCC
(`dd.weather.gc.ca/.../daily/csv/ON/`) and claiming "数据为官方观测值；个别日期存在缺测（标记 M）".

Its own workspace disproves that. It saved exactly two data files, and both are **196-byte
Apache 404 pages**, not CSVs:

```
stations.csv   196 B  <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">…404
yow_2025.csv   196 B  <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">…404
```

So the monthly breakdown and the total were produced **without the data**, and the claim of
observed values with missing-day flags describes a file it never obtained. Per the task's
criterion (a total with unit, source **and the underlying data**, re-checkable from that
source) this is a FAIL. It also silently omitted Nov–Dec 2026 from the requested range.

## V1 — PASS on the stated criteria, with a fabrication note

Every ground-truth field is correct: name **莉拉**, level **700**, popup = 必杀技 **千律**
LV6, XR2-gated, **850 %** damage, **Lv.5 防御力减少(8秒)**, **400 %** damage, 防御力减少 75 %,
沉默.

But it added detail the screenshot's ground truth does not contain: **"1000 EP"**,
**"20 米半径 / 45 度扇形"**, **"BLOSSOM 形态"**, and a specific game title. Those are
inventions around an otherwise correct reading — recorded because V1's purpose is "reading
without inventing", even though the pass criteria only name name/level/popup content.

## V2 — PASS at 15/21, no fabricated connector names

Matched: M2_1, M2_2, DIMM1-4, CODEC, AUDIO, USB2_LAN, HDMI, VGA, L23, U64, L21, U65.
Missing: FCH, PCIE16X, USB31A, USB32A, F_PANEL, F_AUDIO.

It also listed ~197 other designator-shaped tokens — overwhelmingly `C01…C19` passives and
board names (B550/B660/B760) — i.e. it read *more* of the diagram than the 21-label ground
truth rather than inventing connectors. Same 15/21 as every previous Qwen3.8 run.

## V3 — FAIL, the known model-level anchoring error

Size **255/70R18** ✓ and it correctly rejected the prompt's decoys (`245/60R17`, `104T`).
But the load/speed index is **113S** where the truth is **118S**, and it asserted
**COOPER DISCOVERER** as brand/model where the truth is that the brand is **unreadable**.
M+S and the 3PMSF snowflake were read correctly, and it did note "All-Terrain not visible".

Consistent with the ledger: Qwen3.8 gives `113S` on this image across SYCL and both Vulkan
configs, while correctly declining the brand was never reproduced either — a model property,
not a backend one.

## Stability

| check | result |
|---|---|
| crash signatures in 1,456 log lines | **0** (`SIGSEGV` / `device lost` / `ErrorDeviceLost` / alloc failure) |
| requests served | 129 · max single-request prompt **28,537** tokens |
| weighted draft acceptance | **68.46 %** (22,955 / 33,532) |
| `xtx-vulkan` RestartCount | 0 → **0** |
| `b70-sycl` RestartCount | 0 → **0** |

**Concurrent-tenant note:** `b70-sycl` was stopped at 19:00 UTC, during A2/A3, by a
*different* test session — `b70-issue40-test` was up and running on the B70. `docker inspect`
shows `Exited (0)`, `OOMKilled=false`, log ends `cleaning up before exit` (a graceful stop,
not a fault), and this run only ever issued `docker stop xtx-vulkan`. **It was left down
deliberately** so as not to interrupt that session; restoring it is theirs to do.

## Restore verification

`xtx-vulkan` started → `/health` ok → worker `ready` → **routed request through SMG returned a
real completion** (`ok`, `system_fingerprint` `b1-8642541`). SMG's breaker had to be cleared
with `docker restart smg` first (the worker showed `failed` immediately after the restart), as
the skill predicts.

> Observation, not part of the verdict: the running production container reports
> `b1-8642541` = **v0.8.0**, while `:latest` and the golden now point at **v0.9.0**
> (`sha256:001928af…`). The container predates the promote.

## Verdict

**Do not promote b12182 on the strength of this battery.** 6/8 PASS is the same score as every
Qwen3.8 run, the two failures are the two known model-level failures (A3 data acquisition, V3
speed index), and none of the eight tasks exercises what b12182 actually changed over v0.9.0 —
which is decode scheduling and checkpoint internals.

The one result that *is* about this build comes from the separate measurements in
`benchmark/results/2026-11-12-xtx-b12182-vs-v090.md`: **+1.3 % decode on t2 (three-vs-three
residual split, acceptance-controlled), no change on t1**, and **no host-memory reduction from
the reference-counted checkpoints** (peak RSS 6549 MiB on v0.9.0 vs 6552 MiB on b12182, 41 turns
to ~127k depth).

What would change the verdict: a battery that exercises checkpoint restore correctness — the
`e56f006ed` fix (on-device state copy size for quantized KV) means pre-b12182 builds could
restore a wrong state or crash on exactly our q8_0/q4_0 checkpoint path, and no task above
tests that.
