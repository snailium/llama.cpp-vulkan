# Incident log

Stability / regression incidents: GPU dropouts, driver regressions after host OS updates, partial-offload misreads, Mesa pin-check failures in CI. One file per incident: `YYYY-MM-DD-<slug>.md` with host state (`uname -a`, `vulkaninfo --summary`), image digest, what was observed, and the fix/workaround.

No incidents yet — the log starts when the first hardware runs happen. (For reference on format, see the SYCL repo's [`benchmark/incidents/`](https://github.com/snailium/llama.cpp-sycl-intel-b70/tree/main/benchmark/incidents).)
