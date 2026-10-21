#!/usr/bin/env bash
# Usage: run.sh <scenario.lua>   Runs one scenario in a fresh headless nvim inside the sandbox.
SPEC=@RUNS@
export CDV_SPEC=$SPEC
export CDV_PLUGIN=${VARIANT:-@REPO@}
export XDG_DATA_HOME=$SPEC/xdg/data XDG_STATE_HOME=$SPEC/xdg/state XDG_CACHE_HOME=$SPEC/xdg/cache XDG_CONFIG_HOME=$SPEC/xdg/config
# fresh project copy per run
rm -rf "$SPEC/run" && mkdir -p "$SPEC/run" && cp "$SPEC"/proj/*.txt "$SPEC/run/"
cd "$SPEC/run" || exit 1
timeout 60 nvim --headless --clean -c "luafile $SPEC/t/harness.lua" -c "luafile $1" 2>&1 | sed "s#$SPEC#<spec>#g"
