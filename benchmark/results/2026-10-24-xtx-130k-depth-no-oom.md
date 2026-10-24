# 100k/130k depth on the XTX: no OOM — the `count x depth` bound is unreachable

**Date:** 2026-10-24 · **Card:** RX 7900 XTX (Vulkan/RADV) · **Image:** `:latest` = v0.7.0
**Config:** production — Qwen3.8-27B-Q4_K_M, ctx 131072, KV q8_0/q4_0, MTP4, FA on, np 1.

**This report corrects the recommendation in
[2026-10-23-xtx-context-checkpoints-verify.md](2026-10-23-xtx-context-checkpoints-verify.md).**
That report extrapolated the per-token cost to `--ctx-checkpoints x max_depth` and concluded
32 checkpoints would need 108 GiB at 128k, so we should set 4. **The extrapolation is wrong:
it was measured and the model does not OOM.**

## Result

A growing conversation was driven until it hit the context ceiling. It reached
**130,588 tokens** (the 41st turn was rejected with
`request (133852 tokens) exceeds the available context size (131072 tokens)`), and
**nothing OOM'd at any point.**

| config | peak host RSS | min MemAvailable | peak swap | OOM |
|---|---|---|---|---|
| **production default** (`--cache-ram 8192`, `--ctx-checkpoints 32`) | **6,465 MiB** | 22,040 MiB | 1,619 MiB | **no** |
| `--cache-ram 0`, `--ctx-checkpoints 32` | 6,503 MiB | 21,706 MiB | 1,619 MiB | no |
| `--cache-ram 0`, `--ctx-checkpoints 0` | **1,860 MiB** | 26,600 MiB | 1,605 MiB | no |

All three ran inside a 22 GiB cgroup cap (`--memory 22g --memory-swap 22g`) purely as a
guard so that if the projection had been right, the OOM would have killed the container and
not the host. It was never approached.

So at 130k depth the **checkpoint cost is 6,503 - 1,860 = 4,643 MiB (~4.5 GiB)**, not the
108 GiB the linear model predicted. **The prediction "past 32k it will OOM" is falsified.**

## Why the linear model failed: the live set saturates

Production-default run, RSS by conversation depth:

| turn | depth (cache_n) | RSS MiB |
|---|---|---|
| 0 | 0 | 2,015 |
| 1 | 3,262 | 2,495 |
| 2 | 6,526 | 2,946 |
| 5 | 16,318 | 4,260 |
| **10** | **32,638** | **6,367** |
| 15 | 48,963 | 6,383 |
| 20 | 65,288 | 6,397 |
| 30 | 97,938 | 6,432 |
| 39 | **127,323** | **6,465** |

Growth is linear up to ~32k depth and then **completely plateaus**: +98 MiB while depth
quadrupled from 32k to 127k. Eviction bounds the live set, so `ctxcp x current_depth` is an
upper bound that a real conversation never approaches.

**This also explains the earlier 8-turn result.** That run showed a clean +455 MiB per turn
and I read it as unbounded accumulation. It was linear only because 8 turns had not yet
reached the point where the live set saturates. Same config, 41 turns, 4.5 GiB total.

**What I cannot yet explain:** the saturated plateau (~4.6 GiB) is much smaller than
`16 spacing x avg 65k tok x 27.7 KB` would suggest, so the count of *live* checkpoints must be
well under the theoretical 32, and something beyond plain count-eviction is involved
(`--checkpoint-min-step` pruning, or checkpoints only being created when a slot is actually
rolled back rather than on every extension). Reported as measured; the mechanism is not
identified.

## What this does NOT rule out

The workload here is a **monotonically growing conversation**, which never forces a rollback.
The BC-250 evidence that worried us — 21 identical copies of one 5,893-token checkpoint — came
from an **agentic loop**, where tool results rewrite the tail and the slot is rolled back
repeatedly. That shape can plausibly hold a fuller, deeper live set than this run did.

So the honest statement is: **for a long single conversation the default is safe (4.5 GiB at
130k); for a rollback-heavy agent loop it has been shown to churn on a different model, and
our own agent tasks peaked at 20,579 tokens, where 32 checkpoints cost ~3.4 GiB (measured in
the 8-turn phase) — also safe.**

## Revised recommendation

**Leave `--ctx-checkpoints` at its default 32.** Do not set 4.

The 4 recommendation assumed an unreachable worst case and would have cost 28 of the 32
rollback points for memory that is not actually consumed. There is no measured OOM risk at
100k-130k depth with the production configuration.

If a future workload is shown to churn checkpoints (agent loops with heavy tail rewriting),
the cheap hedge is `--ctx-checkpoints 8`–`16`, not 4: the measured saturated cost is ~4.5 GiB
at 130k, so there is room, and a lower count only affects rollback granularity, not decode
speed (the ~18 % decode penalty measured on the BC-250 applies only to `0`).

## Method notes

- Container capped at 22 GiB so a genuine OOM would land inside the container. `b70-sycl`
  was stopped for the whole run: an OOM during `xe_svm_init` has permanently wedged the B70
  before, and the OOM killer must never be able to reach an `xe` process.
- RSS read from the container's init PID (`docker inspect --format {{.State.Pid}}`);
  `pgrep` on the host does not match a containerised cmdline and silently returns 0.
- Depth taken from the server's own `cache_n` (conversation length), not `prompt_n` (the
  per-turn delta), and cross-checked against the server's `stop processing: n_tokens`.

## Artifacts

`/models/ckpt/` on `.101`: `deep.log`, `deep.json`, `iso.log`, `iso_cram0_ctxcp32.json`,
`iso_cram0_ctxcp0.json`, `deep.py`, `run_deep.sh`, `run_iso.sh`.
