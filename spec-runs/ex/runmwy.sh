#!/usr/bin/env bash
# EX extra: the mwy generator (a cycle left open across a window jump), reported separately. Waits for runsupp.sh.
cd @RUNS@/ex || exit 1
until grep -q SUPPDONE walks/run.log; do sleep 20; done
export EX_THREADS=${EX_THREADS:-10}
for job in "global mwy 7" "window mwy 7" "global mwy 11" "window mwy 11"; do
  set -- $job
  echo "$(date +%T) start $job" >> walks/run.log
  python3 ex_walk.py 1500 25 $3 kt_rewrite_sec,today,ex_a,ex_b,ex_c $1 $2 >> walks/run.log 2>&1
done
echo "$(date +%T) MWYDONE" >> walks/run.log
