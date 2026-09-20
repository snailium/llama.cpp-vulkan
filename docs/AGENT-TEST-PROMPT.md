# Agent Test Prompt - Vulkan image validation

This file is the standing instruction an automated agent follows when a new
Vulkan image issue is opened. It is read by the `dsh-github-image-watch` webhook
rule, which passes its contents as the first prompt of a new Session, followed by
the issue metadata and body.

Keeping the instructions here rather than inside the plugin means the procedure
can evolve with the repository.

---

Test the newly built llama.cpp **Vulkan** image described by the issue appended to
this prompt.

## 0. Load the procedure skills first

Before anything else, call the `skill` tool for these, in order:

1. **`backend-test-suite`** - the card-agnostic battery: task definitions, the
   isolated harness invocation, the mandatory per-task metrics, the report template.
2. **`xtx-backend-test`** - the 7900 XTX half: golden config, RADV/ICD pinning,
   the 24 GB VRAM cliff.
3. **`b70-backend-test`** - the B70 half: golden config, card exclusivity.

Do not start testing before reading them. They contain the exact commands and the
failure signatures that make results interpretable.

## 1. Identify what you are testing

- Read `docs/GOLDEN-CONFIG.md` in this repository. Every parameter comes from there.
- Record the **digest** you actually pulled, not just the tag.
- Note the llama.cpp version, Mesa version, and the image tag from the issue, and
  compare with the previous baseline. **A Mesa bump is a bigger change than a
  llama.cpp bump on this backend** and deserves its own line in the report.

## 2. Test BOTH cards, sequentially, one at a time

This image has two supported targets and **both must be tested** - but **never at
the same time**.

**Why sequential:** the two cards back one production router (SMG). While one card
is under test, the other must stay up and serving so the router can keep the
platform available. Running both tests at once would take down both cards.

Order does not matter; pick one and finish it before starting the other:

- **B70 (Intel Arc Pro B70)** - `VK_DRIVER_FILES=.../intel_icd.json`, ctx 98304, f16 KV
- **7900 XTX (AMD RX 7900 XTX)** - `VK_DRIVER_FILES=.../radeon_icd.json`, ctx 131072, q4_0 KV

**The two configs are different - do not reuse one for the other.** The 7900 XTX's
24 GB is the binding constraint; see §5 of `GOLDEN-CONFIG.md`.

For **each** card:

1. Stop only the production container on **that** card. Leave the other card's
   container running and serving.
2. Baseline the other container's `RestartCount` before the run; re-check after.
   A value that grew means the run leaked outside its card.
3. Run the full suite (t1-t5 + V1-V3) with that card's golden config.
4. Restore the production container on that card and **verify it actually serves**
   (`/health` ok, model loaded) before moving to the next card.
5. Write a separate results section per card.

Never stop, restart or remove a production container without the user's explicit
consent - ask first, and name exactly which container you need down and for how long.

## 3. Report per task, per card

For every task on every card, give:

| Field | Meaning |
|---|---|
| fill | prefill throughput, tokens/s |
| TTFT | time to first token, seconds |
| decode | generation throughput, tokens/s |
| draft acceptance | accepted / generated, block-weighted |

Plus, per card: any crash, OOM, restart, SIGSEGV, allocation failure, device loss -
with the log line that shows it; and `RestartCount` / `OOMKilled` from `docker inspect`.

**Always state the KV precision next to decode numbers.** Vulkan runs the XTX at
q4_0 KV while the SYCL golden runs q8_0, so a Vulkan-vs-SYCL decode comparison is
**not** a pure backend comparison. Say so rather than letting the number imply it.

Do not extrapolate. Report only what you measured, and say which numbers you could
not measure and why.

## 4. Decide - the promote gate depends on the channel

The image tag tells you which channel you are validating. **The two channels have
different gates**, and this is deliberate:

### `server-dev-*` (dev channel)

- **7900 XTX passing is sufficient to promote.**
- If the B70 fails, that **does not block promotion** and must **not** be reported
  as a blocker: the B70 has the SYCL route as its production path, so a Vulkan
  regression on that card costs nothing.
- Report the B70 result anyway, clearly marked as **non-gating**.

### `server-m*` stable releases (stable channel)

- **Both cards must pass.** A stable tag is the platform's fallback promise, so a
  card that fails would leave that card without a working stable image.
- If either card fails, **do not promote**, and say which card and how it failed.

### In both cases

- If you judge the change not worth shipping even when green, **say that** - not
  shipping is a valid outcome and should be recorded as one.
- If you promoted, do it via `scripts/promote-vulkan-image.sh <digest> vX.Y` and
  state the digest you promoted.
- Do not guess or extrapolate numbers. Report only what you measured, and say which
  numbers you could not measure.
