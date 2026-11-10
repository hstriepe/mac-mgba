#!/bin/bash
# Builds GB App Builder (with the player template inside) and copies it to build/GB App Builder.app.
#   scripts/build-app.sh            Release, signed with the Developer ID (project.yml)
#   CONFIG=Debug scripts/build-app.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Release}"
cd "$ROOT"
[ -f build/dats/gba.dat ] || scripts/fetch-dats.sh || echo "warning: no DATs (offline?); games are named after their files"
xcodegen generate --quiet
xcodebuild -project GBAppBuilder.xcodeproj -scheme GBAppBuilder -configuration "$CONFIG" \
	-derivedDataPath build/DerivedData build | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true
APP="build/DerivedData/Build/Products/$CONFIG/GB App Builder.app"
[ -d "$APP" ] || { echo "build failed" >&2; exit 1; }
rm -rf "build/GB App Builder.app"
ditto "$APP" "build/GB App Builder.app"
codesign --verify --deep --strict "build/GB App Builder.app"
echo "build/GB App Builder.app ($(du -sh "build/GB App Builder.app" | cut -f1), $CONFIG, mGBA $(cat "build/GB App Builder.app/Contents/Resources/mgba-version.txt"))"
