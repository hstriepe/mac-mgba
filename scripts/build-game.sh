#!/bin/bash
# Builds one game app from the command line with the builder in build/ (scripts/build-app.sh makes it):
#   scripts/build-game.sh "/Volumes/Shared/RETRO_GAMES/ROMs/gba/Advance Wars (USA) (Rev 1).zip" [--out apps] [--name …] [--set gb.model=CGB] …
# Default output: apps/ in this repository. "GB App Builder" --help lists every option.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILDER="$ROOT/build/GB App Builder.app/Contents/MacOS/GB App Builder"
[ -x "$BUILDER" ] || { echo "no builder yet: scripts/build-app.sh" >&2; exit 1; }
[ $# -ge 1 ] || { "$BUILDER" --help; exit 2; }
ROM="$1"; shift
case " $* " in *" --out "*) exec "$BUILDER" --rom "$ROM" "$@" ;; esac
exec "$BUILDER" --rom "$ROM" --out "$ROOT/apps" "$@"
