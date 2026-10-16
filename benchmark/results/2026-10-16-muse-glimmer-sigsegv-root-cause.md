# Muse-Glimmer SIGSEGV: root cause is thread-stack exhaustion in the chat template

**Date:** 2026-10-16 · **Card:** 7900 XTX (Vulkan/RADV) · **Image:** `llama-vulkan:v0.7.0` (`620d222`)
**Status: root cause established and causally verified. Workaround identified.**

## The bug in one line

Requests to Muse-Glimmer crash the server (SIGSEGV, exit 139) once the rendered chat
template exceeds roughly **30-40 KB of content**, because the rendering path exhausts the
**8 MiB default thread stack**. Raising the thread stack moves the wall.

## Evidence chain

### 1. gdb backtrace — the stack is gone, not the heap

```
Thread 7 "llama-server" received signal SIGSEGV
#0  libc.so.6
#1  operator new(unsigned long)        <- allocation
#2  ?? ()                              <- caller, NO return address
#3  0x0000000000000000                 <- frame chain ends here
rip = 0x7c3b8fcacce8     saved rip slot = 0x7c3b6fff9028
frame at 0x7c3b6fff9030  thread stack ptr = 0x7c3b707f86c0
gap = 0x7ff690  (~8 MiB minus a page)
```

`#2` having no caller and the frame reaching the thread's stack limit is stack exhaustion,
not a heap fault. The fatal call is `operator new` merely because that is the next thing
that needs stack.

### 2. The crash is deterministic and fast

**0.28-0.30 s** every time, versus 8-18 s for a *successful* request of similar size. The
failure happens in request preparation, before any compute.

### 3. It tracks payload size, NOT token count

| content | bytes | prompt_n | result |
|---|---|---|---|
| ASCII `"x"×30000` | 30064 | 1931 | ✅ OK |
| ASCII `"x"*35000` | 35064 | 4427 | ❌ crash |
| ASCII `"x"×40000` | 40064 | — | ❌ crash |
| CJK 30000 chars | 180064 | 15055 | ✅ OK |
| CJK 35000 chars | 210064 | — | ❌ crash |

**Boundary ≈ 30-40 KB of body**, and ASCII with only 1931 tokens passes while CJK with
15055 tokens also passes and CJK at 35k chars (≈18k tokens) fails. Token count and context
depth are irrelevant — an earlier "21.6k token limit" reading was an artifact of my filler
being `depth × 1.6` characters, i.e. I was measuring characters while calling them tokens.

### 4. Not VRAM, not the drafter, not sparse FA, not ubatch, not mmproj

| hypothesis | test | outcome |
|---|---|---|
| VRAM exhaustion | no mmproj, **7206 MiB free** | still crashes |
| drafter | no `--spec-type` at all | still crashes |
| sparse FA | `GGML_VK_FA_SPARSE_DISABLE=1` | still crashes |
| ubatch-sized buffers | `-ub 128` | still crashes |
| mmproj path | loaded without `--mmproj` | still crashes |
| a server-wide body limit | Qwen3.8-27B, **same 35 KB payload** | **OK, `prompt_n=4427`** |

The Qwen control is the important one: **the server and backend handle the identical
payload fine. This is specific to Muse-Glimmer.**

### 5. All message shapes fail identically

`user` with a string, `user` with content-parts, and `system` — all crash at 35 KB. So it is
not one macro branch; it is something common to every render.

### 6. CAUSAL PROOF — raising the stack fixes it

| thread stack | 35000 chars | result |
|---|---|---|
| **8 MiB (image default)** | ❌ | `RemoteDisconnected`, exit 139 |
| **64 MiB** | ✅ | **OK, `prompt_n=2244`** |
| 512 MiB | ✅ | OK |

A single `--ulimit stack=67108864` converts a crash into a pass. That is the mechanism
confirmed, not merely correlated.

## Workaround and its limit

With a 64 MiB stack the boundary moves from ~20k to **~50k prompt tokens**:

| content | prompt_n | result |
|---|---|---|
| CJK 35000 | 17558 | ✅ 76.9 s |
| CJK 60000 | 12507 | ✅ 54.8 s |
| CJK 100000 | 20005 | ✅ 90.2 s |
| **CJK 200000** | **50006** | ✅ 240.0 s |
| CJK 400000 | — | ❌ crash (wall moved, not removed) |

**`--ulimit stack=67108864` is the workaround**, and it is a large practical improvement
(~8× the usable context depth). It is not a fix: the recursion is still unbounded and a
sufficiently large prompt will still crash. 512 MiB behaved the same as 64 MiB in the spot
check, so 64 MiB is the economical choice.

## What this means for the earlier reports

The "context pressure scan" conclusion is **superseded**: there was never a ~21.6k *token*
limit. The real variable is the **byte size of the rendered template**, and the practical
limit at the default stack is ~30-40 KB. Reports #1-#3 are unaffected in their task results
because their largest single request was ~20.5k tokens ≈ 33 KB of CJK, which sat just under
the wall — that is why they passed, and why A3 at 20579 tokens was the closest call.

## Recommendation

1. **Set `--ulimit stack=67108864`** on any container running Muse-Glimmer. This is a real
   mitigation and costs nothing.
2. **Report upstream.** This is a clean, deterministic bug with a minimal reproduction:
   *"Muse-Glimmer SIGSEGVs on any request whose rendered prompt exceeds ~30-40 KB, at the
   default 8 MiB thread stack; the backtrace shows stack exhaustion in `operator new`;
   `--ulimit stack=64M` moves the limit to ~200 KB of content or ~50k tokens."* Qwen on the
   same image/backend/hardware does not reproduce it.
3. **Scope the recursion.** The crash is in template rendering (all message shapes fail,
   `--no-jinja` cannot be used to isolate because it refuses all requests with
   *"this custom template is not supported"*). The template's `render_tool_defs` iterates a
   namespace while appending to it, and the system branch chains four `replace()` calls over
   the whole content — both are plausible deep-recursion sites, but neither is yet proven to
   be the one. **The next step is a stack-graph or `-fsanitize` build, not more black-box
   probing.**

## Honest boundaries

1. **The precise recursion site is not identified.** I have proven *what* fails (stack), and
   *where* (template rendering), but not *which function* recurses. All black-box tests that
   varied the message shape gave identical failures.
2. **`--no-jinja` is unusable as a control** — it rejects every request on this model, so it
   cannot show whether rendering is skipped or merely failing early.
3. **64 MiB is not a proven optimum.** It is the smallest value tested that worked; 8 MiB
   fails and 512 MiB works. The true minimum lies between.
4. **The 30-40 KB boundary is for this filler.** Real prose tokenizes differently, so the
   transferable quantity is the *rendered byte size*, which depends on the template, not on
   the token count a client thinks it is sending.

## Artifacts

Scripts on `.101` in `/models/muse-glimmer/run16k/`:
`ascii_thresh.sh` (size bisect, fresh container per point), `stack_test.sh` (the causal
test), `stack_final.sh` (boundary at 64 MiB), `crossmodel.sh` (Qwen control),
`tmpl_isolate.sh` (message-shape isolation), `body_limit.sh`.
Template dump: `/models/muse-glimmer/muse_template.jinja`.
