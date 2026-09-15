#!/usr/bin/env python3
"""t1/t2 direct-streaming client for the B70 backend test suite.

Measures TTFT + decode t/s + draft acceptance for the fixed t1/t2 prompts via
the OpenAI-compatible endpoint, using the official Qwen3.8-27B sampling params.

Usage:
  BACKEND_URL=http://host:port/v1/chat/completions MODEL=... OUT=t1.json python3 t12_client.py t1
"""
import os, json, time, urllib.request

URL = os.environ["BACKEND_URL"]
MODEL = os.environ["MODEL"]

PROMPTS = {
    "t1": "制作一个网页，列出从公元996年到公元1024年间世界上发生的大事件。请输出完整的HTML代码，用中文。",
    "t2": "制作一张SVG，解释宇宙大爆炸理论。请输出完整的SVG代码，文字用中文。",
}

# Official Qwen3.8-27B non-thinking sampling (HF model card).
SAMPLING = {"temperature": 0.7, "top_p": 0.80, "top_k": 20, "min_p": 0.0,
            "presence_penalty": 1.5, "frequency_penalty": 0.0, "repeat_penalty": 1.0}


def run(key):
    pl = {"model": MODEL,
          "messages": [{"role": "user", "content": PROMPTS[key]}],
          "max_tokens": 32768, "stream": True,
          "stream_options": {"include_usage": True},
          "chat_template_kwargs": {"enable_thinking": False, "preserve_thinking": False},
          **SAMPLING}
    req = urllib.request.Request(URL, data=json.dumps(pl).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    ttft = None
    content, timings = [], None
    r = urllib.request.urlopen(req, timeout=3600)
    for raw in r:
        line = raw.decode(errors="replace").strip()
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
            d = ch.get("delta", {})
            if d.get("content"):
                if ttft is None:
                    ttft = time.time() - t0
                content.append(d["content"])
    e2e = time.time() - t0
    text = "".join(content)
    t = timings or {}
    row = {
        "task": key,
        "ttft_s": round(ttft, 2) if ttft else None,
        "e2e_s": round(e2e, 1),
        "prompt_n": t.get("prompt_n"),
        "prefill_tps": round(t.get("prompt_per_second", 0), 1),
        "pred_n": t.get("predicted_n"),
        "decode_tps": round(t.get("predicted_per_second", 0), 1),
        "draft_acc": round(t.get("draft_n_accepted", 0) / t.get("draft_n", 1), 3) if t.get("draft_n") else None,
        "chars": len(text),
    }
    # completeness sanity for the artifact itself
    row["has_html"] = ("<html" in text.lower() or "<!doctype" in text.lower()) if key == "t1" else None
    row["has_svg"] = ("<svg" in text.lower()) if key == "t2" else None
    row["closes_doc"] = ("</html>" in text.lower()) if key == "t1" else ("</svg>" in text.lower())
    out = os.environ.get("OUT", f"{key}_result.json")
    with open(out, "w") as f:
        json.dump({"metrics": row, "content": text}, f, ensure_ascii=False, indent=1)
    print(json.dumps(row, ensure_ascii=False), flush=True)
    print("saved", out, flush=True)


if __name__ == "__main__":
    import sys
    run(sys.argv[1])
