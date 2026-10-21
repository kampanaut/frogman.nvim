#!/usr/bin/env bash
# EX supplementary: a restore-heavy key mix, single window, global view. Waits for runall.sh to finish.
cd @RUNS@/ex || exit 1
until grep -q ALLDONE walks/run.log; do sleep 20; done
export EX_THREADS=${EX_THREADS:-10}
for seed in 7 11; do
  echo "$(date +%T) start global rheavy $seed" >> walks/run.log
  python3 ex_walk_rh.py 1500 25 $seed kt_rewrite_sec,ex_a,ex_b,ex_c global rheavy >> walks/run.log 2>&1
done
echo "$(date +%T) SUPPDONE" >> walks/run.log
