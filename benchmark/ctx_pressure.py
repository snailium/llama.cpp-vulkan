#!/usr/bin/env python3
"""Context pressure test: does the VRAM headroom survive long prompts?

The question this answers is NOT "how fast is long context" - it is whether a
build with only ~400 MiB free can allocate the larger graph buffers that long
prompts require, or whether it OOMs / silently degrades.

So VRAM is sampled continuously from a background thread *while* each request
runs, and the minimum observed free value is the headline number. A single
reading before or after a request would miss the peak allocation.

Sampling is inherited from the server (only max_tokens/stream are sent).

Usage:
  PRESSURE_URL=http://127.0.0.1:PORT/v1/chat/completions MODEL=<id> \
  DEPTHS=4096,16384,32768,65536,100000 MAX_OUT=96 OUT=results.json \
  python3 ctx_pressure.py
"""
import json
import os
import re
import threading
import time
import urllib.request

URL = os.environ["PRESSURE_URL"]
MODEL = os.environ["MODEL"]
MAX_OUT = int(os.environ.get("MAX_OUT", "96"))
DEPTHS = [int(x) for x in os.environ.get("DEPTHS", "4096,16384,32768,65536").split(",")]
OUT = os.environ.get("OUT", "pressure.json")
VRAM_USED = "/sys/class/drm/card2/device/mem_info_vram_used"
VRAM_TOTAL = "/sys/class/drm/card2/device/mem_info_vram_total"

TOTAL = int(open(VRAM_TOTAL).read().strip()) // 1048576


def free_mib():
    return TOTAL - int(open(VRAM_USED).read().strip()) // 1048576


class VramSampler(threading.Thread):
    """Sample free VRAM continuously; keep the minimum seen."""

    def __init__(self, interval=0.05):
        super().__init__(daemon=True)
        self.interval = interval
        self.stop_flag = threading.Event()
        self.samples = []

    def run(self):
        while not self.stop_flag.is_set():
            try:
                self.samples.append(free_mib())
            except Exception:
                pass
            self.stop_flag.wait(self.interval)

    def stop(self):
        self.stop_flag.set()
        self.join(timeout=5)
        return (min(self.samples) if self.samples else None,
                max(self.samples) if self.samples else None,
                len(self.samples))


WORDS = "人工智能深度学习神经网络推理加速内存带宽量化矩阵笛卡尔坐标系高维张量图计算数据流并行化"


def filler(n_chars):
    return "".join(WORDS[i % len(WORDS)] for i in range(n_chars))


def call(prompt_text):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt_text}],
        "max_tokens": MAX_OUT,
        "stream": True,
    }).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    ttft = None
    out = 0
    timings = None
    err = None
    try:
        with urllib.request.urlopen(req, timeout=3600) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                p = line[5:].strip()
                if p == "[DONE]":
                    break
                try:
                    obj = json.loads(p)
                except Exception:
                    continue
                if obj.get("timings"):
                    timings = obj["timings"]
                for ch in obj.get("choices", []):
                    d = ch.get("delta") or {}
                    if d.get("content"):
                        if ttft is None:
                            ttft = time.time() - t0
                        out += 1
    except Exception as e:
        err = f"{type(e).__name__}: {e}"
    return {"ttft_s": round(ttft, 3) if ttft else None,
            "wall_s": round(time.time() - t0, 3),
            "out_tok": out, "timings": timings, "error": err}


def main():
    rows = []
    print(f"total VRAM {TOTAL} MiB; free at start {free_mib()} MiB")
    for depth in DEPTHS:
        # ~1.6 chars/token for this filler, plus a short question tail
        n_chars = int(depth * 1.6)
        prompt = filler(n_chars) + "\n\n请用一句话总结上面这段文字的主题。"
        print(f"\n=== depth ~{depth} ({len(prompt)} chars) ===", flush=True)

        s = VramSampler()
        s.start()
        res = call(prompt)
        mn, mx, n = s.stop()

        t = res["timings"] or {}
        row = {
            "target_depth": depth,
            "prompt_tok": t.get("prompt_n"),
            "vram_free_min_mib": mn,
            "vram_free_max_mib": mx,
            "vram_samples": n,
            "ttft_s": res["ttft_s"],
            "wall_s": res["wall_s"],
            "completion_tok": t.get("predicted_n"),
            "prefill_tps": (round(t["prompt_n"] / res["ttft_s"], 2)
                            if t.get("prompt_n") and res["ttft_s"] else None),
            "decode_tps": (round(t.get("predicted_per_second"), 2)
                           if t.get("predicted_per_second") else None),
            "accept_rate": (round(100.0 * t["draft_n_accepted"] / t["draft_n"], 2)
                            if t.get("draft_n") else None),
            "error": res["error"],
        }
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        if res["error"]:
            print("  -> request FAILED; stopping the scan here", flush=True)
            break
        time.sleep(3)

    with open(OUT, "w") as f:
        json.dump({"total_mib": TOTAL, "rows": rows}, f, ensure_ascii=False, indent=2)
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()