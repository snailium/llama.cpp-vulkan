# Archive notes — server-m26.2-v0.8.0-20261028-1750

| Item | Value |
|---|---|
| Tested digest | `sha256:842e09ddd3ffd79b740a180db88f9e5e396060ec70d334d58c2788a4b11b2bc6` |
| Harness digest | `sha256:1780ca835360cf592779a07584fd1cf265ad29b7cb77cd844ae06442b10fdb11` |
| Skill sha256 | `8af83da14abfa1408204e2eff762470c8dba0e8e4c5dae5893ee1656d1546a53` |
| Tag as promoted | `:stable` = `:v0.8.0` = `:server-m26.2-v0.8.0-20261028-1750` |

Contents: `REPORT.md`, the B70 T1/T2 documents with the code fence stripped (`b70-t1.html`,
`b70-t2.svg` — the B70 T2 response wrapped its SVG in prose, so the extracted block is what is filed),
and the A1–A3 sessions for both cards in both forms (`.jsonl.zstd` byte-exact as dsh wrote them, and
decompressed `.jsonl`).

## Known gaps in this archive

1. **The XTX T1/T2 documents are missing.** The B70 direct-task runs reused the same output filenames as
   the XTX runs, so `results/t1_html.json` and `results/t2_svg.json` hold the B70 output by the end of the
   run. The XTX T1/T2 **verdicts and metrics are unaffected and are recorded in REPORT.md** (both PASS,
   graded structurally at the time: balanced HTML ending at `</html>`; well-formed XML with a single
   `<svg>` root and `viewBox`), but the generated bodies themselves were not preserved. No duplicate of the
   B70 files has been filed under an XTX name.
2. **The B70 A3 session ends at the 1 h timeout** (`rc=124`); it is archived as-is, uncut, so the loop it
   got into is inspectable.
3. **The XTX server log is not filed here** (it is several MB of per-request timings); the per-request
   numbers extracted from it are in REPORT.md.
