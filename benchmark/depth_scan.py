#!/usr/bin/env python3
"""Depth-scan: measure decode t/s and TTFT at increasing context depths.

One chat request per depth: the user message itself is the KV filler (prefill),
then we measure the decode of max_tokens tokens at that depth via response timings.
Usage: DEPTH_SCAN_URL=http://host:port/v1/chat/completions MODEL=/models/... python3 depth_scan.py
"""
import os, json, time, urllib.request

URL = os.environ["DEPTH_SCAN_URL"]
MODEL = os.environ["MODEL"]
MAX_OUT = int(os.environ.get("MAX_OUT", "96"))
DEPTHS = [int(x) for x in os.environ.get("DEPTHS", "1024,16384,32768,65536").split(",")]
KV_LABEL = os.environ.get("KV_LABEL", "?")

# varied Chinese syllables (avoid single-char repetition collapse)
WORDS = "人工智能深度学习神经网络推理加速内存带宽量化矩阵笛卡尔坐标系高维张量图计算数据流并行化"
def filler(n_chars):
    return ("".join(WORDS[i % len(WORDS)] for i in range(n_chars)))

def call(prompt_text, extra):
    pl = {"model": MODEL, "messages": [{"role": "user", "content": prompt_text}],
          "max_tokens": MAX_OUT, "temperature": 0.0, "stream": True,
          "stream_options": {"include_usage": True}}
    pl.update(extra)
    req = urllib.request.Request(URL, data=json.dumps(pl).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    content = []
    timings = None
    r = urllib.request.urlopen(req, timeout=1800)
    for raw in r:
        line = raw.decode(errors="replace").strip()
        if not line.startswith("data:"): continue
        p = line[5:].strip()
        if p == "[DONE]": break
        try: obj = json.loads(p)
        except Exception: continue
        if obj.get("timings"): timings = obj["timings"]
        for ch in obj.get("choices", []):
            d = ch.get("delta", {})
            if d.get("content"): content.append(d["content"])
    e2e = time.time() - t0
    return "".join(content), timings, e2e

# calibration: measure prompt_n for a known char count
probe_n = 4000
_, pt, _ = call(filler(probe_n), {})
if pt:
    rate = pt["prompt_n"] / probe_n
    print(f"calib: {probe_n} chars -> {pt['prompt_n']} tok (rate {rate:.3f} tok/char)", flush=True)
else:
    print("calib FAILED - no timings", flush=True); rate = 0.5

results = []
for D in DEPTHS:
    chars = int(D / rate)
    content, t, e2e = call(filler(chars), {})
    if not t:
        print(f"depth {D}: NO TIMINGS (len={len(content)})", flush=True); continue
    row = {
        "kv": KV_LABEL, "target_depth": D,
        "prompt_n": t.get("prompt_n"), "cache_n": t.get("cache_n"),
        "ttft_s": round(t.get("prompt_ms", 0) / 1000, 2),
        "prefill_tps": round(t.get("prompt_per_second", 0), 1),
        "gen_n": t.get("predicted_n"), "decode_tps": round(t.get("predicted_per_second", 0), 1),
        "draft_acc": round(t.get("draft_n_accepted", 0) / t.get("draft_n", 1), 3),
        "e2e_s": round(e2e, 1),
    }
    results.append(row)
    print(json.dumps(row, ensure_ascii=False), flush=True)

out = os.environ.get("OUT", f"depthscan_{KV_LABEL}.json")
json.dump(results, open(out, "w"), ensure_ascii=False, indent=1)
print("saved", out, flush=True)