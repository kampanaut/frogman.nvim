#!/usr/bin/env bash
# WV copy of rows.sh. Usage: rows_b.sh <name> "<seq>" <view> <variant[,variant...]>   ('today' = the repo, through run_b.sh)
# Rows saved to kt/rows_b/<name>.<view>.<variant>.txt
SPEC=@RUNS@
name=$1; seq=$2; view=$3
mkdir -p $SPEC/kt/rows_b
IFS=, read -ra vs <<< "$4"
for v in "${vs[@]}"; do
  out=$SPEC/kt/rows_b/$name.$view.$v.txt
  if [ "$v" = today ]; then CDV_SEQ="$seq" CDV_VIEW=$view bash $SPEC/t/run_b.sh $SPEC/t/wv_seqrows.lua > $out
  else CDV_SEQ="$seq" CDV_VIEW=$view VARIANT=$SPEC/variants/$v bash $SPEC/t/runv_b.sh $SPEC/t/wv_seqrows.lua > $out; fi
  cat $out
done
