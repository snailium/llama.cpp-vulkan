#!/usr/bin/env python3
"""Re-run T1 on the XTX N times to test determinism.

Prompt is read from the skill file at run time (Rule 5c).
"""
import json, os, re, sys, time, urllib.request
from html.parser import HTMLParser

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "skill"))
from prompt_source import load_prompts

SKILL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "skill", "SKILL.md")
BASE = sys.argv[1]; MODEL = sys.argv[2]; OUT = sys.argv[3]; N = int(sys.argv[4])

def strip_fence(c):
    m = re.match(r"\s*```[a-zA-Z0-9]*\s*\n(.*?)\n?\s*```\s*$", c or "", re.S)
    return (m.group(1) if m else (c or "")).strip()

def grade(doc):
    stack, bad = [], []
    class P(HTMLParser):
        VOID={"area","base","br","col","embed","hr","img","input","link","meta","source","track","wbr"}
        def handle_starttag(self,t,a):
            if t not in self.VOID: stack.append(t)
        def handle_endtag(self,t):
            if stack and stack[-1]==t: stack.pop()
            else: bad.append(t)
    P().feed(doc)
    opens=len(re.findall(r'<div\b',doc)); closes=len(re.findall(r'</div>',doc))
    return {"balanced": not bad and not stack,
            "html/head/body": all(f"<{t}" in doc for t in ("html","head","body")),
            "ends_html": doc.endswith("</html>"),
            "div_open":opens,"div_close":closes,"div_delta":opens-closes,
            "unmatched_end":len(bad),"unclosed":len(stack)}

P = load_prompts(SKILL)
os.makedirs(OUT, exist_ok=True)
print(f"prompt t1_html ({len(P['t1_html'])} chars): {P['t1_html'][:40]}...")
for i in range(1, N+1):
    payload={"model":MODEL,"messages":[{"role":"user","content":P["t1_html"]}],
             "max_tokens":32768,"stream":True,
             "chat_template_kwargs":{"enable_thinking":False}}
    req=urllib.request.Request(BASE.rstrip("/")+"/v1/chat/completions",
        data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"})
    t0=time.time(); ttft=None; buf=[]; finish=None
    with urllib.request.urlopen(req,timeout=3600) as r:
        for raw in r:
            line=raw.decode("utf-8","replace").strip()
            if not line.startswith("data:"): continue
            d=line[5:].strip()
            if d=="[DONE]": break
            try: o=json.loads(d)
            except Exception: continue
            for ch in o.get("choices") or []:
                if ch.get("finish_reason"): finish=ch["finish_reason"]
                pc=(ch.get("delta") or {}).get("content")
                if pc:
                    if ttft is None: ttft=time.time()-t0
                    buf.append(pc)
    doc=strip_fence("".join(buf)); g=grade(doc)
    ok = g["balanced"] and g["html/head/body"] and g["ends_html"] and finish=="stop"
    open(os.path.join(OUT,f"t1_rep{i}.html"),"w").write(doc)
    print(f"run {i}: {'PASS' if ok else 'FAIL'} chars={len(doc)} "
          f"div={g['div_open']}/{g['div_close']} delta={g['div_delta']:+d} "
          f"unmatched_end={g['unmatched_end']} unclosed={g['unclosed']} "
          f"finish={finish} ttft={round(ttft,2) if ttft else '?'}s wall={round(time.time()-t0,1)}s")
