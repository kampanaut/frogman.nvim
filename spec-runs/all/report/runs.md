| Run | What it shows | Code |
|---|---|---|
| `<sandbox>/all/all_walk.py 1500 25 <seed> all_fixed,today <view> <single\|mw\|mwy\|rheavy>`, through `<sandbox>/all/run_matrix.sh` | the numbers, seeds 7, 11 and 13, both views | every fix, today's code |
| the same with `ALL_TAG=.r2` and `.r3`, seed 7, window view, `mw` and `mwy` | repeatability | every fix, today's code |
| the same with `ALL_TAG=.p2 ALL_JOBPFX=other-path-` (other job folders, so other file hashes) | repeatability across file paths | every fix |
| `t/ex_route.lua` with `EX_MORE="R S"` | the ten-key route (T189) | every fix |
| `t/wv_jump.lua`, `t/wv_dup.lua`, `CDV_VIEW=global` and `window` | T175, T176 | every fix |
| `t/wv_seqrows.lua` with `CDV_SEQ="ea eb SP WP ec SP F"`, `CDV_VIEW=window`, `CDV_TIMES=1`, 5 times | the tie's shortest route (T197) | every fix |
| `t/wv_seqrows.lua` with `CDV_SEQ="ea SP ec Y1 F"`, both views, `CDV_TIMES=1` | landing after a cancel (T198) | every fix |
| `t/all_q9.lua` (`ALL_TOGGLE=1` for the round trip); `t/wv_seqrows.lua` with `CDV_SEQ="ea eb G ec ed ee X2 R R"` | the pick note (T172, T155) | every fix, today's code |
| `t/wv_probe.lua`, both views | the window view still re-ranks | every fix |

- `t/…` runs go through `<sandbox>/t/runv.sh` with `VARIANT=<sandbox>/variants/all_fixed`, or `<sandbox>/t/run.sh` for today's code.
- **The walk tooling** is in `<sandbox>/all/`:
  - `all_walk.py` is the earlier packets' generator, unchanged, with every walk set in one script. Seeds 7 and 11 draw the same walks as before.
  - Each walk runs in its own job folder, `<sandbox>/alljobs/<code>-<view>-<set>-<seed>-<walk>`. A re-run uses the same paths, and so the same file hashes.
  - `all_runseq.sh` runs one walk, through the earlier per-step scripts `<sandbox>/ex/ex_seq.lua` (one window) and `<sandbox>/ex/ex_seq_mw.lua` (several windows).
  - `all_scan.py` does the counts, reusing the earlier scan's I23 lookup (`<sandbox>/ex/ex_scan.py`).
  - `all_table.py` builds the tables.
  - `all_cmp.py` does the step-for-step comparisons.
- **The tooling was checked against the earlier runs.** Under the global view, today's code matches the earlier packets' walk files step for step in every set they share: one window, several windows and cycles left open, seeds 7 and 11, 9,000 of 9,000 walks.
- **Walk files:** `<sandbox>/all/walks/<code>-<view>-<set>-1500-25-<seed>[.r2|.r3|.p2].jsonl`, where `<code>` is `all_fixed` or `today`, and `<set>` is `single`, `mw`, `mwy` or `rheavy`.
