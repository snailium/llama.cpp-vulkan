#!/usr/bin/env python3
"""A1 review-coverage observation (reported, never gating).

Counts real files in the clone the agent made, then the paths it actually
touched (read file_path values inside the clone + real filenames appearing in
bash commands). Naive bash substring counting over-counts badly
(backend-test-suite warns: it reported 23 where the truth was 14), so the bash
side only accepts tokens that look like a file that exists in the inventory.
"""
import json, os, re, subprocess, sys

sess, root = sys.argv[1], sys.argv[2]
out = subprocess.run(["zstd", "-dc", sess], capture_output=True)
inv = set()
for dp, dns, fns in os.walk(root):
    if ".git" in dp.split(os.sep):
        continue
    for f in fns:
        inv.add(os.path.relpath(os.path.join(dp, f), root))

touched, read_calls = set(), 0
for line in out.stdout.decode("utf-8", "replace").splitlines():
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get("type") != "tool/call":
        continue
    d = e.get("data") or {}
    a = d.get("arguments")
    if isinstance(a, str):
        try:
            a = json.loads(a)
        except Exception:
            a = {}
    a = a or {}
    if d.get("name") == "read":
        fp = str(a.get("file_path", ""))
        read_calls += 1
        if "/mqtt2ha/" in fp:
            touched.add(fp.split("/mqtt2ha/", 1)[1])
    elif d.get("name") == "bash":
        for m in re.findall(r"(?<![\w/.-])([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.+-]+)*\.[A-Za-z0-9]+)\b",
                            str(a.get("command", ""))):
            if m in inv:
                touched.add(m)

hit = touched & inv
print(f"files touched / inventory : {len(hit)} / {len(inv)}  ({len(hit)/len(inv):.0%})")
print(f"read calls               : {read_calls}")
print(f"missed                   : {', '.join(sorted(inv - hit))}")
