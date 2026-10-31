#!/usr/bin/env python3
"""Direct (non-agent) tasks for the issue-16 Vulkan dev run: T1, T2, V1-V3.

Prompts are parsed from the staged copy of backend-test-suite/SKILL.md at run
time (never transcribed). Only two request fields are added on top of the
backend's deployed config: chat_template_kwargs (thinking off, task protocol)
and max_tokens (generation cap). stream=True is transport, needed to measure TTFT.

Usage:
    python3 run_direct.py t1_html t2_svg v1 v2 v3
"""
import base64
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "skill"))
from prompt_source import load_prompts, skill_sha256  # noqa: E402

BASE = os.environ.get("BACKEND", "http://192.168.111.101:18092")
MODEL = os.environ.get("MODEL_ID", "/models/Qwen3.8-27B-Q4_K_M.gguf")
SKILL = os.environ.get("SKILL_FILE", os.path.join(HERE, "skill", "SKILL.md"))
RESULTS = os.path.join(HERE, "results")
MAX_TOKENS = 32768

IMAGES = {
    "v1": (os.path.join(HERE, "skill", "game_screenshot_Lila.jpg"), "jpeg"),
    "v2": (os.path.join(HERE, "skill", "motherboard_layout.png"), "png"),
    "v3": (os.path.join(HERE, "skill", "tire_25570R18.jpg"), "jpeg"),
}


def build_payload(task, prompt):
    content = [{"type": "text", "text": prompt}]
    if task in IMAGES:
        path, fmt = IMAGES[task]
        b64 = base64.b64encode(open(path, "rb").read()).decode()
        content.append(
            {"type": "image_url", "image_url": {"url": f"data:image/{fmt};base64,{b64}"}}
        )
    return {
        "model": MODEL,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": MAX_TOKENS,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }


def run(task, prompt):
    payload = build_payload(task, prompt)
    req = urllib.request.Request(
        BASE + "/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    parts, usage, timings = [], {}, {}
    finish = None
    t_send = time.time()
    t_first = None
    raw_path = os.path.join(RESULTS, f"{task}_raw.jsonl")
    with urllib.request.urlopen(req, timeout=3600) as r, open(raw_path, "w") as raw:
        for bline in r:
            line = bline.decode("utf-8", "replace")
            raw.write(line)
            s = line.strip()
            if not s.startswith("data: "):
                continue
            data = s[6:]
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            if obj.get("usage"):
                usage = obj["usage"]
            if obj.get("timings"):
                timings = obj["timings"]
            for ch in obj.get("choices") or []:
                if ch.get("finish_reason"):
                    finish = ch["finish_reason"]
                delta = ch.get("delta") or {}
                piece = delta.get("content") or ""
                if piece:
                    if t_first is None:
                        t_first = time.time()
                    parts.append(piece)
    t_end = time.time()

    text = "".join(parts)
    result = {
        "task": task,
        "prompt_chars": len(prompt),
        "choices": [{"message": {"content": text}, "finish_reason": finish}],
        "usage": usage,
        "timings_server": timings,
        "client": {
            "ttft_s": round(t_first - t_send, 3) if t_first else None,
            "wall_s": round(t_end - t_send, 3),
            "decode_s": round(t_end - t_first, 3) if t_first else None,
        },
    }
    with open(os.path.join(RESULTS, f"{task}_result.json"), "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)

    pn = (usage.get("prompt_tokens") if usage else None) or timings.get("prompt_n")
    cn = (usage.get("completion_tokens") if usage else None) or timings.get("predicted_n")
    ttft = result["client"]["ttft_s"]
    dec = result["client"]["decode_s"]
    prefill = (pn / ttft) if (pn and ttft) else None
    decode = (cn / dec) if (cn and dec) else None
    print(f"\n=== {task} ===")
    print(f"  content chars      : {len(text)}")
    print(f"  finish_reason      : {finish}")
    print(f"  prompt_tokens      : {pn}")
    print(f"  completion_tokens  : {cn}")
    print(f"  TTFT               : {ttft} s")
    print(f"  prefill (client)   : {prefill:.1f} tok/s" if prefill else "  prefill: n/a")
    print(f"  decode  (client)   : {decode:.1f} tok/s" if decode else "  decode: n/a")
    if timings:
        print(f"  server prefill     : {timings.get('prompt_per_second'):.1f} tok/s"
              f"  (prompt_n={timings.get('prompt_n')}, cache_n={timings.get('cache_n')})")
        print(f"  server decode      : {timings.get('predicted_per_second'):.1f} tok/s"
              f"  (predicted_n={timings.get('predicted_n')})")
        dn, da = timings.get("draft_n"), timings.get("draft_n_accepted")
        if dn:
            print(f"  draft acceptance   : {da}/{dn} = {da / dn:.3f}")
    return result


def main():
    tasks = sys.argv[1:]
    prompts = load_prompts(SKILL)
    print(f"skill sha256: {skill_sha256(SKILL)}")
    print(f"backend     : {BASE}  model={MODEL}")
    print(f"prompts     : {sorted(prompts)}")
    for t in tasks:
        if t not in prompts:
            raise SystemExit(f"unknown task {t}")
        run(t, prompts[t])


if __name__ == "__main__":
    main()
