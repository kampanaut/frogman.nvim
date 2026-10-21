# spec-runs

These are the runs behind `what-is-cavediver.md`: the headless test harness, the scenarios cited as `[run …]`, the random-walk scripts, the variants cited as `[sim …]`, and the research write-ups.

Everything that can be regenerated was left out: walk output, job folders and the full plugin copies. A variant is kept as a patch against `lua/`, and the walks are seeded, so the same command gives the same walks.

## Setting up

Nothing here runs in place. Make a sandbox outside the repo first:

```sh
spec-runs/setup.sh /tmp/cavediver-sandbox
```

This copies the files there, fills in the real paths, and rebuilds every variant from `variants/*.patch` onto the current `lua/`. A patch that no longer applies means the code has changed under it.

## Running

From inside the sandbox:

- One scenario on today's code: `bash t/run.sh "$PWD/t/i23_route.lua"`
- The same scenario on a variant: `VARIANT=$PWD/variants/all_fixed bash t/runv.sh "$PWD/t/i23_route.lua"`
- Walks with every fix in: `python3 all/all_walk.py 1500 25 7 all_fixed,today window mw`. The arguments are walks, keys per walk, seed, variants, `global` or `window`, and `single`, `mw`, `mwy` or `rheavy`.

Scenarios print one row per action with its result: `⦉ternary⦊ [current] ⟦secondary⟧   dtm{…} dsm{…}`.

## What's where

- `t/`: `harness.lua`, `fmt.lua` (the row format), the runners, and every scenario.
- `proj/`: the small files the scenarios open.
- `rt/`, `kt/`, `ex/`, `all/`, `q6/`: walk generators, scans and variant builders, one folder per research round. `packets/` has each round's write-up.
- `variants/`: one patch per variant. `all_fixed.patch` has every fix decided on 2026-10-20 and 2026-10-21.
- `desk_sync_pending.md`: decisions not yet on the desk.
