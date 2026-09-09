# llama.cpp + Vulkan Tuning Guide — Intel Arc Pro B70 & AMD RX 7900 XTX

Hands-on flags and pitfalls for this repo's image (or any matching `GGML_VULKAN=ON` build). For the reasoning and source data, see [`VULKAN-KNOWLEDGE.md`](./VULKAN-KNOWLEDGE.md).

## 1. Host prerequisites (Linux)

- **Intel B70:** kernel with `xe` (Ubuntu 24.04/26.04 + 6.8+/7.x recommended). No userspace install needed on the host — the container ships ANV.
- **AMD 7900 XTX:** kernel with `amdgpu` (any recent distro kernel). The container ships RADV.
- Add your user to the GPU groups:

```bash
sudo usermod -aG render,video $USER   # then log out / back in
```

- Verify what Vulkan sees **on the host** (this is what the container will use via `/dev/dri`):

```bash
vulkaninfo --summary
# Expect (B70 box):  Intel(R) Arc(TM) Pro B70 Graphics   driverInfo: ANV ...
# Expect (AMD box):  AMD Radeon RX 7900 XTX              driverInfo: RADV ...
```

Record the `driverInfo` line in every benchmark report — it is the single most diagnostic field.

## 2. The build options (already set in `.devops/vulkan.Dockerfile`)

- `-DGGML_VULKAN=ON`
- `-DGGML_BACKEND_DL=ON`
- `-DGGML_CPU_ALL_VARIANTS=ON`
- `-DGGML_NATIVE=OFF` (portable CPU code; the GPU path is Vulkan)
- **No** `GGML_VULKAN_DEBUG`, **no** `GGML_VULKAN_CHECK_RESULTS`, no `DISABLE_*` flags.

Shader AOT: ggml compiles its compute shaders with `glslc` at build time; per-device first-use still happens at runtime and is cached in `~/.cache/llama.cpp` (mount a volume there if you want warm starts across container restarts).

## 3. Mandatory / recommended runtime environment

```bash
# Nothing is *mandatory* for the basic path — Vulkan finds its ICD via the loader.
# Optional, per-card:
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json          # force ANV (B70)
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json  # force RADV (7900 XTX)

# Debugging only — do NOT ship these:
# GGML_VK_DISABLE_COOPMAT2=1    # bypass the Intel coop-mat path (diagnostic)
# GGML_VULKAN_DEBUG=1               # verbose backend logging (needs a debug build to be useful)
```

## 4. ICD selection on multi-GPU / mixed boxes

If a host has **both** an Intel and an AMD GPU, the loader sees both ICDs and llama.cpp enumerates both devices:

- `--device 0` / `--device 1` selects by enumeration order — check with `vulkaninfo --summary` which index is which (order is not guaranteed to match `/dev/dri/renderD*` numbering).
- To make it deterministic, set `VK_DRIVER_FILES` to a single ICD JSON (then only that vendor's devices appear), or restrict the container to one render node:

```bash
docker run --device /dev/dri/renderD128:/dev/dri/renderD128 ...   # B70 only
docker run --device /dev/dri/renderD129:/dev/dri/renderD129 ...   # 7900 XTX only
```

## 5. The offload line — always read it before trusting a benchmark

```bash
# In the server log, look for:
# llama_model_loader: loaded N layers ... n_gpu_layers=NN
```

- `n_gpu_layers` must equal your `--n-gpu-layers` value (999 → all). A **silent partial offload** (less VRAM free than expected, e.g. after a SIGKILL'd previous instance) produces no error and a 2–5× slower "result".
- The classic trap: `SIGKILL` on the server orphans child processes that keep holding VRAM. Use SIGTERM, wait for drain, verify with `vulkaninfo`/`nvidia-smi`-equivalent (for AMD: `rocm-smi` is *not* needed — just check free memory in the loader log).

## 6. KV cache & context per card

| Card | Default | With MTP draft / large ctx |
|------|---------|---------------------------|
| B70 32 GB | `--cache-type-k/v f16`, ctx 96k | `q8_0`, ctx up to 128k (re-verify on Vulkan) |
| 7900 XTX 24 GB | `f16` ≤16k; **`q8_0`** for ≥32k | `q8_0`, keep 27B-class at ≤32k until measured otherwise |

- f16 KV is the fast path and holds up at depth on B70 Vulkan (field report).
- q4_0 KV is **not** recommended past ~16k context (quality + a reported generation-speed cost on Vulkan, per the B70 field report's correction).
- The 24 GB card is the binding constraint for 27B-class: Q4_K_M ≈ 18.9 GB + KV + activations. If you need more context, drop to 8B-class or add a second card (multi-GPU Vulkan is supported upstream; untested here).

## 7. Recommended server invocations

**B70 (Qwen3.8-27B Q4_K_M, no draft):** see [`examples/b70-server.sh`](../examples/b70-server.sh).
**7900 XTX (same model, tighter ctx):** see [`examples/7900xtx-server.sh`](../examples/7900xtx-server.sh).

Both launchers: `--n-gpu-layers 999`, `--flash-attn on`, official Qwen3.8-27B non-thinking sampling (`--temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5 --frequency-penalty 0.0 --repeat-penalty 1.0`), thinking off for artifact tasks via `chat_template_kwargs.enable_thinking=false`.

## 8. Stability notes

- **PCIe:** the SYCL repo's B70 box needed `pcie_aspm=off` (B450 link-training instability). If you see GPU dropouts on the same hardware, apply the same kernel flag — it is driver-stack-agnostic.
- **Driver regressions are real:** a host Mesa/kernel update can change throughput without any image change. Re-run `vulkaninfo --summary` and the T1–T5 suite after any host OS update; log incidents under `benchmark/incidents/`.
- **Warm shader cache:** mount `-v ~/.cache/llama.cpp:/root/.cache/llama.cpp` (or set `XDG_CACHE_HOME`) to avoid first-run shader compilation cost on each container start.

## 9. Quick diagnostic checklist

```bash
# 1. What does the host see?
vulkaninfo --summary | grep -E 'gpu|driverInfo'

# 2. Does the container build pass the Mesa pin-check? (it fails loudly otherwise)
docker build --target server -t llama.cpp-vulkan:server -f .devops/vulkan.Dockerfile .

# 3. Does the server offload fully?
docker run --rm --device /dev/dri -v $PWD/models:/models llama.cpp-vulkan:server \
  -m /models/Qwen3.8-27B-Q4_K_M.gguf --n-gpu-layers 999 --ctx-size 4096 \
  | grep -E 'n_gpu_layers|offload'

# 4. Single-shot sanity (expect finish_reason=stop, sane tg):
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"default","messages":[{"role":"user","content":"Reply with exactly: OK"}],
       "max_tokens":16,"chat_template_kwargs":{"enable_thinking":false}}'
```
