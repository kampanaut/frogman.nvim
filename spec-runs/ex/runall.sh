#!/usr/bin/env bash
# EX: every walk set, in priority order. Log: ex/walks/run.log
cd @RUNS@/ex || exit 1
VS=kt_rewrite_sec,today,ex_a,ex_b,ex_c
export EX_THREADS=${EX_THREADS:-10}
for job in "global single 7" "global single 11" "window single 7" "window single 11" "global mw 7" "window mw 7" "global mw 11" "window mw 11"; do
  set -- $job
  echo "$(date +%T) start $job" >> walks/run.log
  python3 ex_walk.py 1500 25 $3 $VS $1 $2 >> walks/run.log 2>&1
done
echo "$(date +%T) ALLDONE" >> walks/run.log
