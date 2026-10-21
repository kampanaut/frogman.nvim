#!/usr/bin/env bash
# Usage: rt_runseq.sh <jobid> <plugin-dir> "<seq>"   Each job gets its own sandbox under spec/rtjobs/<jobid>.
SPEC=@RUNS@
J=$SPEC/rtjobs/$1
case "$J" in "$SPEC"/rtjobs/?*) ;; *) echo "bad job dir" >&2; exit 1;; esac
rm -rf "$J" && mkdir -p "$J/run" "$J/xdg/data" "$J/xdg/state" "$J/xdg/cache" "$J/xdg/config" || exit 1
cp "$SPEC"/proj/*.txt "$J/run/" || exit 1
export CDV_SPEC=$J CDV_PLUGIN=$2 CDV_SEQ=$3
export XDG_DATA_HOME=$J/xdg/data XDG_STATE_HOME=$J/xdg/state XDG_CACHE_HOME=$J/xdg/cache XDG_CONFIG_HOME=$J/xdg/config
cd "$J/run" || exit 1
timeout 60 nvim --headless --clean -c "luafile $SPEC/t/harness.lua" -c "luafile $SPEC/rt/rt_seq.lua" 2>&1
rm -rf "$J"
