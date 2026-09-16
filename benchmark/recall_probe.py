#!/usr/bin/env python3
"""Exact-recall probe: does KV precision (q4_0 vs q8_0) affect the model's ability
to emit the correct ECCC OGC API endpoint? Same model weights, same sampling.

Scores each sample for the two facts t5 actually needs:
  endpoint : "climate-daily" + "items"   (the OGC API collection path)
  param    : "CLIMATE_IDENTIFIER"        (station filter)
"""
import json, os, urllib.request

TARGETS = [("SYCL_q8_0", "http://192.168.111.101:18080/v1/chat/completions"),
           ("VULKAN_q4_0", "http://192.168.111.101:18090/v1/chat/completions")]
MODEL = "/models/Qwen3.8-27B-Q4_K_M.gguf"
N = int(os.environ.get("N", "8"))

PROMPT = ("查询加拿大环境与气候变化部（ECCC）的历史逐日气象观测数据（climate-daily），"
          "请直接给出：1) 完整的 OGC API 请求 URL 路径；2) 按气候站点 ID 过滤的参数名。"
          "只给 URL 和参数名，不要解释。")


def ask(url):
    pl = {"model": MODEL, "messages": [{"role": "user", "content": PROMPT}],
          "max_tokens": 300, "temperature": 0.7, "top_p": 0.80, "top_k": 20,
          "min_p": 0.0, "presence_penalty": 1.5, "frequency_penalty": 0.0, "repeat_penalty": 1.0,
          "chat_template_kwargs": {"enable_thinking": False, "preserve_thinking": False}}
    r = urllib.request.Request(url, data=json.dumps(pl).encode(),
                               headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=600) as resp:
        d = json.load(resp)
    return d["choices"][0]["message"]["content"]


for label, url in TARGETS:
    ep = pa = both = 0
    samples = []
    for i in range(N):
        try:
            t = ask(url)
        except Exception as e:
            samples.append(f"ERR {e}"); continue
        low = t.lower()
        has_ep = ("climate-daily" in low) and ("items" in low)
        has_pa = "climate_identifier" in low
        ep += has_ep; pa += has_pa; both += (has_ep and has_pa)
        hit = ("EP" if has_ep else "--") + ("/PARAM" if has_pa else "/-----")
        samples.append(f"{hit}: {t[:90].strip()}")
    print(f"=== {label}  (n={N}) ===")
    print(f"    correct endpoint: {ep}/{N}   correct param: {pa}/{N}   BOTH: {both}/{N}")
    for s in samples:
        print("      ", s.replace("\n", " "))
    print()
