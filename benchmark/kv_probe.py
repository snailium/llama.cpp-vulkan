#!/usr/bin/env python3
"""KV-precision probe: SYCL q8_0 (B70) vs Vulkan q4_0 (XTX).

Same weights, same sampling. Four task families, each scored deterministically:
  A. long-context recall   : 20k-token context, needle fact at the start
  B. multi-step arithmetic : chain of additions + final sum
  C. code generation       : Python function with known-correct output
  D. exact entity recall   : names/numbers that must be verbatim

Run: KV_PROBE_N=5 python3 kv_probe.py
"""
import json, os, random, re, time, urllib.request

TARGETS = [("SYCL_q8_0", "http://192.168.111.101:18080/v1/chat/completions"),
           ("VULKAN_q4_0", "http://192.168.111.101:18090/v1/chat/completions")]
MODEL = "/models/Qwen3.8-27B-Q4_K_M.gguf"
N = int(os.environ.get("KV_PROBE_N", "5"))

PARAMS = {"temperature": 0.7, "top_p": 0.80, "top_k": 20, "min_p": 0.0,
          "presence_penalty": 1.5, "frequency_penalty": 0.0, "repeat_penalty": 1.0,
          "chat_template_kwargs": {"enable_thinking": False, "preserve_thinking": False}}


def ask(url, messages, max_tokens):
    pl = dict(PARAMS)
    pl.update({"model": MODEL, "messages": messages, "max_tokens": max_tokens})
    r = urllib.request.Request(url, data=json.dumps(pl).encode(),
                               headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=900) as resp:
        d = json.load(resp)
    return d["choices"][0]["message"]["content"]


def build_needle_context(rng):
    """~20k tokens of filler with one fact planted at the very start."""
    rng.seed(1234)
    needle = "The secret code word for this report is ZEBRA-7741. Remember it exactly."
    filler_words = []
    while len(filler_words) < 19500:
        # deterministic pseudo-random prose, ~4-6 words per sentence
        n = rng.randint(30, 60)
        for _ in range(n):
            filler_words.append(rng.choice(
                "the quick brown fox jumps over lazy dog data stream processing "
                "pipeline model context window token embedding attention layer "
                "gradient descent optimization convergence batch size learning rate "
                "network architecture inference deployment latency throughput memory "
                "cache quantization precision floating point integer matrix vector "
                "operation compute kernel shader dispatch synchronization barrier".split()))
    filler = " ".join(filler_words)
    # chunk into paragraphs to look like a document
    paras, i = [], 0
    while i < len(filler):
        paras.append(filler[i:i + 400]); i += 420
    return needle + "\n\n" + "\n\n".join(paras)


def task_a(rng):
    ctx = build_needle_context(rng)
    msgs = [{"role": "user", "content": ctx + "\n\nWhat is the secret code word mentioned at the start of this document? Answer with only the code word."}]
    def score(t):
        return "ZEBRA-7741" in t.upper()
    return "A_needle_20k", msgs, 50, score


def task_b(rng):
    nums = [rng.randint(100, 999) for _ in range(6)]
    total = sum(nums)
    chain = " + ".join(str(n) for n in nums)
    msgs = [{"role": "user", "content": f"What is {chain}? Answer with just the number."}]
    def score(t):
        return str(total) in t
    return "B_arithmetic", msgs, 30, score


def task_c(rng):
    n = rng.randint(2, 9)
    expected = n * n + 3
    msgs = [{"role": "user", "content":
             f"Write a Python function `f(x)` that returns x squared plus 3. "
             f"In the docstring show exactly one example: what is f({n})? "
             f"Write it as f({n}) = <result>."}]
    def score(t):
        has_def = re.search(r"def\s+f\s*\(", t) is not None
        ex = re.findall(rf"f\({n}\)\s*=\s*(\d+)", t)
        return bool(has_def and any(int(v) == expected for v in ex))
    return "C_code", msgs, 400, score


def task_d(rng):
    facts = [
        ("The capital of Australia is Canberra.", "Canberra"),
        ("Water boils at 100 degrees Celsius at sea level.", "100"),
        ("There are 9 planets in our solar system after Pluto's reclassification.", "9"),
    ]
    q, ans = rng.choice(facts)
    msgs = [{"role": "user", "content": f"State this fact exactly as given: {q} Then answer: what is the key value?"}]
    def score(t):
        return ans in t
    return "D_entity", msgs, 100, score


TASKS = [task_a, task_b, task_c, task_d]

for label, url in TARGETS:
    print(f"=== {label} (n={N}) ===")
    for name in ("A_needle_20k", "B_arithmetic", "C_code", "D_entity"):
        hits = 0
        detail = []
        for i in range(N):
            rng = random.Random(1000 + i)
            tname, msgs, mtok, score = TASKS[ord(name[0]) - ord("A")](rng)
            try:
                t = ask(url, msgs, mtok)
                ok = score(t)
            except Exception as e:
                t, ok = f"ERR {e}", False
            hits += ok
            detail.append(("OK " if ok else "XX ") + t[:70].replace("\n", " "))
        print(f"  {name}: {hits}/{N}")
        for d in detail[:2]:
            print(f"      {d}")
    print()
