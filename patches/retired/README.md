# Retired patches

Kept for history and for the reasoning behind them. Nothing here is applied by CI:
the workflows glob only `patches/*.patch`, never this subdirectory.

## `0001-vulkan-cm1-clamp-A-operand-block-index.patch` — retired 2026-10-31

**Superseded upstream at b12019** by
[`2864937a7`](https://github.com/ggml-org/llama.cpp/commit/2864937a7) — *"vulkan: clamp A
prefetch to end_k in coopmat1 int8 matmul (#30283)"*.

### What it fixed

In the coopmat1 int8 MMQ shader, the **B** operand already clamped its block index past
`end_k`, but the **A** operand did not:

```glsl
pre_a[li * BK_STEP + ks] = block_a_load(ib + ks, loadr_a);   // unguarded
```

When `K` is not a multiple of `BK * BK_STEP`, a k-step past `end_k` read one block beyond the
row. That picks up the next row, or bytes past the tensor, whose f16 scale can be NaN. The
B side was zeroed, so the term contributed nothing *in principle* — but the A scale is read for
all `BK_STEP` steps, so a NaN there poisoned the dot product. Symptom: wrong results, not a
crash.

### Upstream's fix, and why ours is gone

Upstream applied the same expression we did:

```glsl
const uint ib_k = ((blk) + ks * BK < end_k) ? (ib + ks) : ib;
pre_a[li * BK_STEP + ks] = block_a_load(ib_k, loadr_a);
```

and went one step further: `block_a_to_shmem()` gained an `in_bounds` parameter and now
**explicitly zeroes both `d` and `dm`** for k-steps past `end_k`, instead of relying on the
clamped block's scale. That removes the dependency our patch still had, so keeping it would
only pin the build to a stale file layout — which is exactly what happened: the patch stopped
applying at b12019 and failed the 2026-10-31 dev build.

### Verified before retiring

- at b12019 the only remaining `block_a_load()` call uses the clamped `ib_k`
- both `pre_a[...]` write sites are guarded (`ib_k` and `in_bounds`)
- no other shader contains an unguarded `block_a_load(ib + ks)`

### If this ever regresses

Re-create it from the relational description above rather than reusing this file: the diff
context no longer matches and `git apply` will refuse it.

## Note: the stable workflow never applied this patch

While retiring it I diffed the two build workflows and found that `build-stable.yml` has **no
patch step at all** — only `build-dev.yml` globs `patches/*.patch`. So no stable image ever
carried our clamp.

Which stable images actually lacked the fix is a separate question, and the answer is **not**
"all of them":

| stable tag | contains upstream `2864937a7`? | had our clamp? | net |
|---|---|---|---|
| v0.5.0 | no | no | **missing the fix** |
| v0.6.0 | no | no | **missing the fix** |
| v0.7.0 | no | no | **missing the fix** — this was production |
| **v0.8.0** | **yes** (first tag containing it is `b11952`) | no | **has upstream's fix** |

So the divergence mattered for v0.5.0–v0.7.0 only. It had no observed consequence because the
k-past-`end_k` branch only fires when `K` is not a multiple of `BK * BK_STEP` (= 128 on the
dense path) and our models use `K = 256`: the batteries were passing on images missing a fix
whose precondition our shapes never meet. A latent hole, never an active one.

v0.8.0 and everything after it are correct by upstream's own change, which is also why the
v0.8.0 dev-build run at `b12019` failed on the patch: the file had already been rewritten.
Nothing to do now — both workflows agree by having nothing to apply.
