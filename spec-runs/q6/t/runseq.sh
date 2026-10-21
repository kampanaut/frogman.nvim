#!/usr/bin/env bash
# Usage: runseq.sh <jobid> <plugin-dir> "<seq>"   Each job gets its own sandbox under q6/jobs/<jobid>.
Q6=@RUNS@/q6
J=$Q6/jobs/$1
case "$J" in "$Q6"/jobs/?*) ;; *) echo "bad job dir" >&2; exit 1;; esac
rm -rf "$J" && mkdir -p "$J/run" "$J/xdg/data" "$J/xdg/state" "$J/xdg/cache" "$J/xdg/config" || exit 1
cp "$Q6"/../spec/proj/*.txt "$J/run/" || exit 1
export CDV_SPEC=$J CDV_PLUGIN=$2 CDV_SEQ=$3
export XDG_DATA_HOME=$J/xdg/data XDG_STATE_HOME=$J/xdg/state XDG_CACHE_HOME=$J/xdg/cache XDG_CONFIG_HOME=$J/xdg/config
cd "$J/run" || exit 1
timeout 60 nvim --headless --clean -c "luafile $Q6/../spec/t/harness.lua" -c "luafile $Q6/t/seq.lua" 2>&1
rm -rf "$J"
