#!/usr/bin/env bash
# ALL: the whole matrix, then the repeat runs. Log: all/walks/run.log
cd @RUNS@/all || exit 1
export ALL_THREADS=${ALL_THREADS:-12}
for seed in 7 11 13; do
  for gen in single mw mwy rheavy; do
    for view in global window; do
      echo "$(date +%T) start $view $gen $seed" >> walks/run.log
      python3 all_walk.py 1500 25 $seed all_fixed,today $view $gen >> walks/run.log 2>&1
    done
  done
done
echo "$(date +%T) MATRIXDONE" >> walks/run.log
for tag in .r2 .r3; do
  for gen in mw mwy; do
    echo "$(date +%T) start repeat window $gen 7 $tag" >> walks/run.log
    ALL_TAG=$tag python3 all_walk.py 1500 25 7 all_fixed,today window $gen >> walks/run.log 2>&1
  done
done
echo "$(date +%T) REPEATDONE" >> walks/run.log
