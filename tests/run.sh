#!/bin/sh
# Runs the addon's real Lua under stubbed GMod APIs.
#   tests/run.sh             data-safety, kill-tracking and net-protocol checks
#   tests/run.sh --preview   also renders every board page to tests/preview/*.png
# Needs luajit and lua-cjson; the preview also needs python3, Pillow and DejaVu fonts.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
export ADDON="$HERE/../boggle_kills"

luajit "$HERE/test.lua"

if [ "$1" = "--preview" ]; then
    OUT="$HERE/preview"
    mkdir -p "$OUT"
    python3 "$HERE/fontmetrics.py" > "$OUT/fontmetrics.lua"
    luajit "$HERE/render.lua" "$OUT"
    for i in 1 2 3 4 5; do
        python3 "$HERE/render.py" "$OUT/page$i.json" "$OUT/page$i.png" "$ADDON/materials/boggle_kills/logo.png"
    done
fi
