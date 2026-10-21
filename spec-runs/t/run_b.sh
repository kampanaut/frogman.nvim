#!/usr/bin/env bash
# Usage: run.sh <scenario.lua>   Runs one scenario in a fresh headless nvim inside the sandbox.
SPEC=@RUNS@
export CDV_SPEC=$SPEC
export CDV_PLUGIN=@REPO@
export XDG_DATA_HOME=$SPEC/xdg_b/data XDG_STATE_HOME=$SPEC/xdg_b/state XDG_CACHE_HOME=$SPEC/xdg_b/cache XDG_CONFIG_HOME=$SPEC/xdg_b/config
# fresh project copy per run
rm -rf "$SPEC/run_b" && mkdir -p "$SPEC/run_b" && cp "$SPEC"/proj/*.txt "$SPEC/run_b/"
cd "$SPEC/run_b" || exit 1
timeout 60 nvim --headless --clean -c "luafile $SPEC/t/harness.lua" -c "luafile $1" 2>&1 | sed "s#$SPEC#<spec>#g"
