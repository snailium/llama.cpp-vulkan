# B70/RDNA Backend Test Report — 7900 XTX · Vulkan (llama.cpp v0.4.1) on .101

Date: 2026-09-16 (UTC run window 07:26Z - 08:31Z)
Host: **home-ai `.101`** — consolidated dual-GPU box (Arc Pro B70 + RX 7900 XTX)
Backend under test: `xtx-vulkan` — AMD RX 7900 XTX, llama.cpp v0.4.1 Vulkan (RADV), host port **18090**
Golden reference: `b70-sycl` — Intel Arc Pro B70, llama.cpp SYCL/oneAPI, host port 18080 (same host, same model dir)
Harness: `ghcr.io/snailium/dsh-container/dsh:latest` @ `sha256:66f6ea2273887953eaba989e366f34d3d70b93d121b816124e94d31cdce40b5b`
Test home: isolated `DSH_HOME` bind-mount (`benchmark/.xtx-run/dsh-test-home`) — never touches production `~/.dsh`

## Parameter alignment (Vulkan ← SYCL golden)

The Vulkan service was re-aligned to the SYCL golden so both backends run the same workload.
Only two deviations remain, both forced by the 7900 XTX's 24 GB (24560 MiB) and both
validated against community practice:

| Param | SYCL golden (b70-sycl) | XTX Vulkan (now) | Status |
|---|---|---|---|
| model | Qwen3.8-27B-Q4_K_M.gguf | same | ✅ aligned |
| `--ctx-size` | 131072 | **131072** | ✅ aligned |
| MTP | `draft-mtp`, n-max 4, p-min 0.1 | **same** | ✅ aligned |
| vision | `--mmproj` + `--no-mmproj-offload` + `--image-min-tokens 1024` | **same** | ✅ aligned |
| `--flash-attn` | `on` | **`on`** | ✅ aligned |
| `--n-gpu-layers` | 999 | 999 | ✅ aligned |
| sampling / `--reasoning off` / chat-template-kwargs | official Qwen3.8 | identical | ✅ aligned |
| **main KV** | q8_0 / q8_0 | **q4_0 / q4_0** | ⚠️ deviation |
| **draft model + draft KV** | Q8_0 / q8_0 | **Q4_0 / q4_0** | ⚠️ deviation |
| device pinning | `ONEAPI_DEVICE_SELECTOR=level_zero:0` | `--device Vulkan0` + `VK_DRIVER_FILES=…/radeon_icd.json` | host-specific, required |

### Why the two deviations (measured)

| Config tested | ctx | KV | MTP draft | Free VRAM | Decode |
|---|---|---|---|---|---|
| original | 32768 | q8_0 | none (no MTP) | 5245 MiB | 35.5 t/s |
| full golden attempt | 131072 | q4_0 | Q8_0 (3.16 GB) | **218 MiB** | **10.5 t/s** ❌ |
| ctx only | 131072 | q4_0 | none | 3946 MiB | 35.5 t/s |
| ctx halved | 65536 | q4_0 | Q8_0 | 717 MiB | 44–53 t/s |
| **adopted** | **131072** | **q4_0** | **Q4_0 (1.37 GB)** | **298–389 MiB** | **48–58 t/s** |

**Finding — there is a sharp VRAM cliff.** The complete golden set (ctx 131072 + MTP + q4_0 main KV)
*loads* with only 218 MiB free and decode **collapses 3.4× to 10.5 t/s** (GPU still 99% busy at
3094 MHz — i.e. spill/thrash, not a kernel limit). Freeing headroom restores it: 717 MiB → 48 t/s,
298 MiB → 48–58 t/s. So ~0.3 GB free is workable; ~0.2 GB is not.

**Finding — the Q4_0 draft is what makes ctx 131072 + MTP fit at all.** Unsloth's Dynamic-3.0
guidance says to use the Q4_0 MTP module, and it is real: `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` = 1.37 GB
vs Q8_0's 3.16 GB. Downloaded from
[`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) and size-verified
against HF (`x-linked-size: 1369590656`). Dropping the draft KV to q4_0 too is the consistent
companion change. The forum's single-7900XTX MTP+128K configs corroborate q4_0 KV as the enabler
([lcz.me/topic/1744](https://lcz.me/topic/1744), [lcz.me/topic/100](https://lcz.me/topic/100)).

> ⚠️ Comparability caveat: q4_0 KV is a *lower precision* KV than the golden's q8_0, and lower
> KV precision also means less KV read bandwidth. Vulkan-vs-SYCL decode numbers below are therefore
> not a pure backend comparison — they differ in KV precision as well as backend.

## Results Summary

| Task | Status | Key metrics | Notes |
|---|---|---|---|
| t1_html | **PASS** | TTFT 0.55s · prefill 121.4 · dec **90.5 t/s** · acc 0.752 | valid complete HTML (4643 tok) |
| t2_svg | **PASS** | TTFT 0.48s · prefill 131.1 · dec **93.7 t/s** · acc 0.812 | valid complete SVG (8677 tok) |
| t3_security | **PASS** | prefill 313.9 · dec **66.0 t/s** (deep ctx) | full audit 1 High + 4 Medium + 6 Low + priority table |
| t4_hostinfo | **PASS** | prefill 509.3 · dec **87.3 t/s** | JSON matches the real host exactly (i5-7500T, 14 GiB, nvme0n1 465.8 GB, sda 476.9 GB) |
| t5_snowfall | **FAIL** | agent loop | model looped on a non-existent host until denied 227×; **same failure on the B70 control** — not Vulkan-specific |
| V1 game | **PASS** | E2E 79.5s · dec 65.4 t/s | 千律/LV6/850%/Lv5防8s/400%/-1000/75%+沉默 — all correct; occluded panel honestly flagged |
| V2 pcb | **PASS** | E2E 21.4s · dec 70.9 t/s | 12 interfaces (CPU/DIMM1-4/PCIE16X/M2_1-2/HDMI/XGA/USB2_LAN/AUDIO/F_AUDIO/USB3A×2/USB2/SPDIFOUT) — most complete of any backend so far |
| V3 tire | **PASS** | E2E 102.6s · dec 63.9 t/s | 255/70R18 · 118S · BFGoodrich All-Terrain T/A · M+S + 3PMSF (118S is the known unit-OCR misread; truth 112S) |

7/8 PASS. Server-side timings extracted from `slot print_timing` in the container log and split by
wall-clock window; t1/t2/V1-V3 cross-check the client-captured response-body `timings` (they agree,
e.g. V1 65.37 server vs 65.4 client).

## The headline: no deep-context collapse on the 7900 XTX

Same model, same task, same sampling — t3 (codebase security audit, deep agent context):

| Backend | KV | prefill t/s | **decode t/s** |
|---|---|---|---|
| B70 Vulkan (v0.4.1, .102 era) | q8_0 | 124.7 | **5.4** ← collapses |
| B70 SYCL (v0.4.1) | q8_0 | 124.7 | 5.4–22.3 |
| **7900 XTX Vulkan (this run)** | q4_0 | 313.9 | **66.0** |

The 7900 XTX holds **66 t/s at deep context — ~3× the B70 SYCL and ~12× the B70 Vulkan** result.
This is consistent with the B70's collapse being specific to its `FA_SCALAR`-at-`n_rows==1` path
(upstream [ggml-org/llama.cpp#28721](https://github.com/ggml-org/llama.cpp/issues/28721)), and with
RDNA3 not exhibiting that pathology.

## t5 failure (reproduced on the B70 control)

t5 was run **simultaneously on both backends** (separate GPUs) as a KV-precision A/B control:

| Backend | KV | steps | breaker denials | outcome |
|---|---|---|---|---|
| XTX Vulkan | q4_0 | 248+ | **227** | stuck: re-emitted one byte-identical `bash` call 140× |
| B70 SYCL | q8_0 | 108 | 6 | `dsh: PI_AI_ERROR: Context size has been exceeded` (rc=1) |

Both fail. The model hallucinated **`weather.canada.ca`**, which **does not resolve** (verified:
DNS FAIL; the real endpoints `weather.gc.ca` / `api.weather.gc.ca` return 200). It then looped on
the unreachable host rather than switching source. The earlier .102-era B70 run passed this task
(258.6 cm via ECCC) on the *old* harness, so this is a task/agent-behaviour regression, visible on
**both** backends — **not a Vulkan defect**.

Note the q4_0 run degenerated far worse (227 denials vs 6) — consistent with lower KV precision
weakening the model's ability to break out of a loop, though it is also confounded by path choice.

## Harness findings (not backend defects)

1. **The newest `dsh-container:latest` cannot boot headless out of the box.** Its headless profile
   template lists **`dsh-relay`** in `dsh.profile.bundles`, but `dsh-relay` injects `webServer`,
   which the `@deepseek-ai/dsh-headless` bundle explicitly does not mount ("mounts no Host, HTTP
   server, Web runtime"). Result:
   ```
   dsh: cannot create effect on inactive context
   Error: dsh: plugin tree failed to load: dsh: 1 entry did not activate
       dsh-relay: pending (waiting for service: webServer)
   ```
   Fix used here (isolated test home only): drop `dsh-relay` from the bundle list. The template
   should either omit it in headless mode or mark it conditional.
2. **`dsh-repeat-tool-breaker` v0.3.2 works — the alternation loophole is fixed.** On the .102 era,
   v0.1.3 could not fire on A,B,A,B alternation; here it fires correctly (denials observed on
   alternating calls). However, a guard can only *deny* a call — it cannot make the model emit
   different tokens. Once the model is in a denial loop it simply re-emits the denied call, so the
   breaker converts an infinite tool loop into an infinite denial loop rather than ending it.
3. **Non-verbose logs still carry `slot print_timing`**, so per-request prefill/decode is
   recoverable without `-v` (no request bodies in the log). Per-request `timings` JSON is *not*
   in the log without `-v`, but the response body carries it for non-streaming calls.

## Stability

| Check | Result |
|---|---|
| RestartCount | **0** |
| OOMKilled / ExitCode | false / 0 |
| SIGSEGV / device-lost / GGML_ASSERT / vk:: | 0 / 0 / 0 / 0 |
| Container | Up ~1 hour (healthy) |
| `b70-sycl` golden service | untouched, still healthy on :18080 |

The single `abort()` log hit is the benign
`common_fit_params: failed to fit params to free device memory: n_gpu_layers already set by user to 999, abort`.

## Verdict

**The 7900 XTX Vulkan backend on .101 is functionally correct and fast** — 7/8 tasks pass with
outputs equal to or better than the B70 runs, decode 87–94 t/s short-context and 66 t/s at deep
context, with zero crashes across an hour.

Two caveats to carry forward:
1. **State the KV deviation whenever quoting decode numbers.** The alignment to the SYCL golden is
   exact on context, MTP, vision and sampling, but uses q4_0 KV (and a Q4_0 draft) because the
   24 GB card cannot hold q8_0 KV + MTP + 131072. Decode comparisons vs SYCL are therefore not
   KV-precision-matched.
2. **t5 needs attention as a task, not as a backend.** It fails on both backends (agent loops on a
   non-existent weather host). Options: pin the data source in the prompt, or have the harness
   treat repeated identical denied calls as a terminal condition instead of looping.

---

## Addendum — re-run of t3/t4/t5 on the vendored harness (`sha256:675cd420…`)

The image was rebuilt to **vendor its packages** (`/plugs/*.tgz`, pinned as
`file:/plugs/…` — no npm access at start), which fixes the reproducibility issue noted above.
Re-ran t3/t4/t5 against the same `xtx-vulkan` backend.

| Task | Result | Notes |
|---|---|---|
| t4_hostinfo | **PASS** | JSON again matches the real host exactly (i5-7500T, 14 GiB, nvme0n1 465.8 GB, sda 476.9 GB, root 457 GB) |
| t3_security | **PASS** | even more thorough than the first pass — **2 High + 5 Medium + 6 Low** with per-item reasoning |
| t5_snowfall | **FAIL** | looped again, on a *different* invented endpoint (see below) |

**Vendoring: fixed and verified.** `/plugs/` now holds 6 tgz files and the profile template pins
them by exact path — `dsh-repeat-tool-breaker-0.3.3.tgz` installed as **0.3.3** (was 0.3.2 via a
`^0.3.2` range). No network is needed at container start, so the harness is now reproducible.

**`dsh-relay` in the headless bundle list: still broken.** The template still lists `dsh-relay`
in `dsh.profile.bundles`, so a *fresh* `DSH_HOME` still fails to boot exactly as before:

```
dsh: 1 entry did not activate
dsh-relay: pending (waiting for service: webServer)
```

The same local workaround (drop `dsh-relay` from the bundle list in the isolated test home) was
required again. **This is the one remaining blocker for out-of-the-box headless runs.**

**t5 failure mode changed but did not resolve.** This time the model found the correct *host*
(`api.weather.gc.ca`) but invented a non-existent *path*
(`/observations.json?cpuid=YOW`), then re-emitted that byte-identical command **70 times**.
The 0.3.3 breaker denied 83 calls; the model re-emitted anyway. Across this session t5 has now
failed 3/3 on the 7900 XTX and 1/1 on a B70 control run, while passing once on the older harness —
so it is an unstable **task/agent** behaviour, reproducible on more than one backend, not a Vulkan
defect.

The interaction worth fixing is that a guard can only *deny*: once the first informative error has
been seen, every subsequent attempt returns `REPEAT_TOOL_BLOCKED` instead of a fresh result, and the
model stays in the loop. Terminating the turn after N consecutive denials would convert an unbounded
loop into a bounded failure.

---

## Addendum 2 — is t5's failure caused by the q4_0 KV downgrade?

**No.** Tested directly with an exact-recall probe (`recall_probe.py`): same model weights
(`Qwen3.8-27B-Q4_K_M`), same sampling (temp 0.7 / top-p 0.80 / top-k 20 / presence 1.5, thinking off),
only the KV precision differs. 8 samples per backend, asked for the ECCC `climate-daily` OGC API
endpoint and its station-filter parameter:

| Backend | KV | correct endpoint | correct param | both |
|---|---|---|---|---|
| B70 SYCL (golden) | **q8_0** | 3/8 | **0/8** | **0/8** |
| 7900 XTX Vulkan | **q4_0** | 1/8 | **0/8** | **0/8** |

The q8_0 golden backend fails the same probe, so the failure is **not** a quantization artifact.
Both precisions emit fabricated hosts, paths and dataset UUIDs, e.g.
`https://open-data.ecc.gc.ca/collections/climate-daily/items?stn_id=40109` (q8_0) and
`https://open.canada.ca/data/en/dataset/9c03b546-…` (q4_0).

The correct facts the task needs are `api.weather.gc.ca/collections/climate-daily/items` filtered by
`CLIMATE_IDENTIFIER` — **0/8 recalled on both precisions**. This is a model knowledge gap, not a
backend or quantization defect.

It also explains t5's flakiness precisely: the model cannot recall the endpoint, so it guesses. The
one passing run (258.6 cm) reached the right endpoint through **web search**, not memory. t5 therefore
hinges on whether the agent elects to search or to guess. Practical fixes: pin the endpoint/parameter
in the prompt, or require the agent to search before asserting a data source.
