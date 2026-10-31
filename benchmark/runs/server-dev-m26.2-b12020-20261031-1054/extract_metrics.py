#!/usr/bin/env python3
"""Per-task metrics for the agent tasks from llama-server `slot print_timing`.

Capture mode of this run: the server was NOT started with -v (only -lv 4 for the
loader detail), so per-request `timings` JSON is absent from the log and
`slot print_timing` is the only server-side source. Its coverage is partial for
short requests, so every agent row reports "requests that emitted timings",
never the task's true request count.

Tasks run sequentially, so each task is split by a wall-clock window taken from
its dsh session `createdAt` (start) and the run-log mtime (end).

Windows come from a JSON file: {"a1_security": ["<iso start>", "<iso end>"], ...}
"""
import json
import re
import sys
from datetime import datetime, timezone

# loose patterns (llama-server-metrics-extraction: tight ones under-match)
RE_TS = re.compile(r"^(\d{4}-\d\d-\d\dT[\d:.]+Z)")
RE_PROMPT = re.compile(
    r"prompt eval time\s*=\s*([\d.]+) ms /\s*(\d+) tokens")
RE_EVAL = re.compile(r"\|\s+eval time\s*=\s*([\d.]+) ms /\s*(\d+) tokens")
RE_ACC = re.compile(r"draft acceptance = ([\d.]+) \(\s*(\d+) accepted /\s*(\d+) generated")
RE_TASK = re.compile(r"id\s+\d+ \| task (\d+) \|")
RE_POS = re.compile(r"acc per pos = \(([^)]*)\)")


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def main(logpath, windows_path):
    windows = json.load(open(windows_path))
    rows = {}   # task -> {req: {...}}
    pos = {}    # task -> list of tuples (per-position acceptance)
    for line in open(logpath, encoding="utf-8", errors="replace"):
        m = RE_TS.match(line)
        if not m or "print_timing" not in line:
            continue
        ts = parse_ts(m.group(1))
        task_id = RE_TASK.search(line)
        if not task_id:
            continue
        tid = task_id.group(1)
        row = rows.setdefault(tid, {}).setdefault(
            "meta", {"start": ts, "end": ts, "pn": 0, "pms": 0.0,
                     "dn": 0, "dms": 0.0, "acc": 0, "gen": 0,
                     "ttfts": [], "n": 0})
        row["end"] = ts
        if pm := RE_PROMPT.search(line):
            row["pms"] += float(pm.group(1))
            row["pn"] += int(pm.group(2))
            row["ttfts"].append(float(pm.group(1)) / 1000.0)
            row["n"] += 1
        if em := RE_EVAL.search(line):
            row["dms"] += float(em.group(1))
            row["dn"] += int(em.group(2))
        if am := RE_ACC.search(line):
            row["acc"] += int(am.group(2))
            row["gen"] += int(am.group(3))
        if ppm := RE_POS.search(line):
            vals = [float(x) for x in ppm.group(1).split(",") if x.strip()]
            if vals:
                pos.setdefault(tid, []).append(vals)

    # map windows -> task names, keeping only rows fully inside a window
    out = {}
    for name, (ws, we) in windows.items():
        ws, we = parse_ts(ws), parse_ts(we)
        agg = {"pn": 0, "pms": 0.0, "dn": 0, "dms": 0.0, "acc": 0, "gen": 0,
               "ttfts": [], "n": 0}
        for tid, d in rows.items():
            r = d["meta"]
            if ws <= r["start"] and r["end"] <= we:
                for k in ("pn", "pms", "dn", "dms", "acc", "gen", "n"):
                    agg[k] += r[k]
                agg["ttfts"] += r["ttfts"]
        tt = sorted(agg["ttfts"])
        med = tt[len(tt) // 2] if tt else None
        out[name] = {
            "requests_with_timings": agg["n"],
            "prompt_tokens": agg["pn"],
            "prefill_tok_s": round(agg["pn"] / (agg["pms"] / 1000), 1) if agg["pms"] else None,
            "ttft_median_s": round(med, 2) if med else None,
            "ttft_max_s": round(tt[-1], 2) if tt else None,
            "completion_tokens": agg["dn"],
            "decode_tok_s": round(agg["dn"] / (agg["dms"] / 1000), 1) if agg["dms"] else None,
            "draft_accepted": agg["acc"],
            "draft_generated": agg["gen"],
            "accept_pct": round(100 * agg["acc"] / agg["gen"], 1) if agg["gen"] else None,
        }
    # per-position acceptance (equal weight per request, as the skill prescribes)
    print(json.dumps(out, indent=1))
    if pos:
        print("\nper-position draft acceptance (mean over requests):")
        for tid, tuples in pos.items():
            n = max(len(t) for t in tuples)
            means = []
            for i in range(n):
                col = [t[i] for t in tuples if len(t) > i]
                means.append(round(sum(col) / len(col), 3) if col else None)
            print(f"  task {tid} (n={len(tuples)}): {means}")
    return out


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
