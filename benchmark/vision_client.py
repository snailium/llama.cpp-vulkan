#!/usr/bin/env python3
"""V1-V3 vision client for the B70 backend test suite.

Sends each test image base64-inline with the fixed prompt, thinking off,
max_tokens 800, and records the answer plus timings.

Usage:
  BACKEND_URL=http://host:port/v1/chat/completions MODEL=... IMGDIR=/path \
    OUTDIR=.v041-run python3 vision_client.py V1
"""
import os, json, time, base64, mimetypes, urllib.request, sys

URL = os.environ["BACKEND_URL"]
MODEL = os.environ["MODEL"]
IMGDIR = os.environ["IMGDIR"]
OUTDIR = os.environ.get("OUTDIR", ".")

TASKS = {
    "V1": ("game_screenshot_Lila.jpg",
           "这是游戏角色必杀技效果界面截图。请仔细阅读屏幕上实际显示的文字，逐项回答：1)必杀技名称和等级；2)对范围内敌人造成多少%伤害、附带什么减益、持续几秒；3)对前排敌人造成多少%伤害、附带什么减益、持续几秒；4)消耗多少EP；5)增益信息面板里列出的具体效果(如防御降低多少%、沉默几秒)。逐项简答，直接给数字，不要编造。"),
    "V2": ("motherboard_layout.png",
           "这是主板点位图。请逐一列出你看到的所有接口/元件标注：CPU插座、DIMM内存槽、PCIE插槽、M.2、各类IO接口(USB/AUDIO/HDMI/XGA/LAN等)。条目式输出,尽量完整。"),
    "V3": ("tire_25570R18.jpg",
           "这是轮胎侧壁照片。请读取侧壁上可见的模压文字：1)尺寸规格(如255/70R18);2)载重指数和速度等级(如118S);3)品牌和型号名;4)认证/适用标识(M+S,三峰雪花等)。看不清就直说看不清,不要编造品牌型号。"),
}


def run(key):
    fname, prompt = TASKS[key]
    path = os.path.join(IMGDIR, fname)
    mime = mimetypes.guess_type(fname)[0] or "image/jpeg"
    b64 = base64.b64encode(open(path, "rb").read()).decode()
    pl = {"model": MODEL,
          "messages": [{"role": "user", "content": [
              {"type": "text", "text": prompt},
              {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}}]}],
          "max_tokens": 800, "temperature": 0.2, "stream": False,
          "chat_template_kwargs": {"enable_thinking": False, "preserve_thinking": False}}
    req = urllib.request.Request(URL, data=json.dumps(pl).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    e2e = time.time() - t0
    text = d["choices"][0]["message"]["content"]
    t = d.get("timings", {}) or {}
    row = {"task": key, "image": fname,
           "e2e_s": round(e2e, 1),
           "ttft_s": round(t.get("prompt_ms", 0) / 1000, 2),
           "prompt_n": t.get("prompt_n"),
           "decode_tps": round(t.get("predicted_per_second", 0), 1),
           "pred_n": t.get("predicted_n")}
    with open(os.path.join(OUTDIR, f"{key}_result.json"), "w") as f:
        json.dump({"metrics": row, "content": text}, f, ensure_ascii=False, indent=1)
    print(json.dumps(row, ensure_ascii=False), flush=True)
    print("--- answer ---", flush=True)
    print(text, flush=True)


if __name__ == "__main__":
    run(sys.argv[1])
