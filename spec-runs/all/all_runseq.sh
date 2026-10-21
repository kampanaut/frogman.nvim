#!/usr/bin/env bash
# ALL copy of ex/ex_runseq.sh (job dirs under spec/alljobs/). Usage: all_runseq.sh <jobid> <plugin-dir> "<seq>" <view> <seq.lua>
# Each job gets its own sandbox under spec/alljobs/<jobid>. <view> is "global" or "window", set right after setup().
SPEC=@RUNS@
J=$SPEC/alljobs/$1
case "$J" in "$SPEC"/alljobs/?*) ;; *) echo "bad job dir" >&2; exit 1;; esac
rm -rf "$J" && mkdir -p "$J/run" "$J/xdg/data" "$J/xdg/state" "$J/xdg/cache" "$J/xdg/config" || exit 1
cp "$SPEC"/proj/*.txt "$J/run/" || exit 1
export CDV_SPEC=$J CDV_PLUGIN=$2 CDV_SEQ=$3 CDV_VIEW=$4
export XDG_DATA_HOME=$J/xdg/data XDG_STATE_HOME=$J/xdg/state XDG_CACHE_HOME=$J/xdg/cache XDG_CONFIG_HOME=$J/xdg/config
cd "$J/run" || exit 1
timeout 60 nvim --headless --clean -c "luafile $SPEC/t/harness.lua" -c "luafile $SPEC/ex/ex_view.lua" -c "luafile $5" 2>&1
rm -rf "$J"
