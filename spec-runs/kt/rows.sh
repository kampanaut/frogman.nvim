#!/usr/bin/env bash
# Usage: rows.sh <name> "<seq>" <variant[,variant...]>   Rows for a walk sequence under each variant, saved to kt/rows/<name>.<variant>.txt
SPEC=@RUNS@
name=$1; seq=$2
IFS=, read -ra vs <<< "$3"
for v in "${vs[@]}"; do
  CDV_SEQ="$seq" VARIANT=$SPEC/variants/$v bash $SPEC/t/runv.sh $SPEC/t/rt_seqrows.lua > $SPEC/kt/rows/$name.$v.txt
  echo "== $v"; cat $SPEC/kt/rows/$name.$v.txt
done
