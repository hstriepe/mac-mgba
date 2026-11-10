#!/bin/bash
# Xcode build phase of the GBAppBuilder target: puts the files the builder hands to every app into its Resources.
#   BIOS/        the repository's bios/*.bin (git-ignored: your own dumps), if present
#   DATs/        build/dats/{gb,gbc,gba}.dat (scripts/fetch-dats.sh), if present
#   SystemIcons/ mGBA's gb/gbc/gba icons (fallback app icons)
#   mgba-version.txt
set -euo pipefail
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
mkdir -p "$DEST/BIOS" "$DEST/DATs" "$DEST/SystemIcons"
shopt -s nullglob
for f in "$ROOT"/bios/*.bin; do cp -p "$f" "$DEST/BIOS/"; done
for f in "$ROOT"/build/dats/*.dat; do cp -p "$f" "$DEST/DATs/"; done
for s in gb gbc gba; do cp -p "$ROOT/mgba/res/$s-icon.svg" "$DEST/SystemIcons/"; done
git -C "$ROOT/mgba" describe --tags --always > "$DEST/mgba-version.txt"
[ -n "$(ls "$DEST/BIOS")" ] || echo "warning: no BIOS files in $ROOT/bios; built apps will run without a BIOS"
[ -n "$(ls "$DEST/DATs")" ] || echo "warning: no DATs in build/dats; run scripts/fetch-dats.sh"
