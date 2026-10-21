#!/usr/bin/env bash
# Usage: spec-runs/setup.sh <dest-dir>
# Makes a working sandbox at <dest-dir>: copies these files there, fills in the
# @RUNS@ and @REPO@ placeholders with real paths, and rebuilds every variant
# (a patched copy of the plugin) from variants/*.patch. Runs write their output
# (run dirs, walk files, job dirs) inside <dest-dir>, never in the repo.
set -euo pipefail
if [ $# -ne 1 ]; then
	echo "Usage: $0 <dest-dir>" >&2
	exit 1
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CDV_REPO:-$(cd "$HERE/.." && pwd)}" # CDV_REPO overrides it, to test a copy kept elsewhere
mkdir -p "$1"
DEST="$(cd "$1" && pwd)"
case "$DEST" in
	"$REPO"|"$REPO"/*) echo "Pick a <dest-dir> outside the repo." >&2; exit 1 ;;
esac

cp -r "$HERE"/. "$DEST"/
rm -f "$DEST/setup.sh"

# Fill in the placeholders.
grep -rIl -e '@RUNS@' -e '@REPO@' "$DEST" | while read -r f; do
	sed -i -e "s#@RUNS@#$DEST#g" -e "s#@REPO@#$REPO#g" "$f"
done

# Rebuild the variants from their patches.
for p in "$DEST"/variants/*.patch; do
	name="$(basename "$p" .patch)"
	case "$name" in
		q6_*) out="$DEST/q6/variants/${name#q6_}" ;;
		*) out="$DEST/variants/$name" ;;
	esac
	rm -rf "$out"
	mkdir -p "$out"
	cp -r "$REPO/lua" "$out/lua"
	patch -s -p1 -d "$out" < "$p"
done

# Output folders the walk scripts write into (left out of the repo copy).
mkdir -p "$DEST"/rt/walks "$DEST"/rt/walks_b "$DEST"/ex/walks "$DEST"/all/walks "$DEST"/q6/jobs \
	"$DEST"/rtjobs "$DEST"/rtjobs_b "$DEST"/exjobs "$DEST"/alljobs

chmod +x "$DEST"/t/*.sh "$DEST"/*/*.sh 2>/dev/null || true
echo "Sandbox ready at $DEST"
