#!/usr/bin/env bash
# EX: the rest of runall.sh's queue, reordered (multi-window first). Waits for the running window-single-7 set.
cd @RUNS@/ex || exit 1
while pgrep -f "ex_walk.py 1500 25 7 kt_rewrite_sec,today,ex_a,ex_b,ex_c window single" >/dev/null; do sleep 10; done
VS=kt_rewrite_sec,today,ex_a,ex_b,ex_c
export EX_THREADS=${EX_THREADS:-10}
for job in "global mw 7" "window mw 7" "global mw 11" "window mw 11" "window single 11"; do
  set -- $job
  echo "$(date +%T) start $job" >> walks/run.log
  python3 ex_walk.py 1500 25 $3 $VS $1 $2 >> walks/run.log 2>&1
done
echo "$(date +%T) ALLDONE" >> walks/run.log
