#!/bin/bash
# Archives GB App Builder (Release, player template inside) into Xcode's Archives folder, so it shows in
# Xcode's Organizer, signed with an Apple Development identity of team D6WY385Q4D.
#   scripts/archive-app.sh
#   IDENTITY="Developer ID Application" scripts/archive-app.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${IDENTITY:-Apple Development}"
TEAM="${TEAM:-D6WY385Q4D}"
cd "$ROOT"
[ -f build/dats/gba.dat ] || scripts/fetch-dats.sh || echo "warning: no DATs (offline?); games are named after their files"
xcodegen generate --quiet
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/GB App Builder $(date +%Y-%m-%d\ %H.%M.%S).xcarchive"
echo "Archiving with \"$IDENTITY\" (team $TEAM) → $ARCHIVE"
xcodebuild -project GBAppBuilder.xcodeproj -scheme GBAppBuilder -configuration Release \
	-derivedDataPath build/DerivedData -archivePath "$ARCHIVE" \
	CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" archive \
	| grep -E "error:|warning:|ARCHIVE (SUCCEEDED|FAILED)" || true
APP="$ARCHIVE/Products/Applications/GB App Builder.app"
[ -d "$APP" ] || { echo "archive failed" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=|^TeamIdentifier=" | head -2
codesign -dvv "$APP/Contents/Resources/Template/GB Player.app" 2>&1 | grep -E "^Authority=" | head -1 | sed 's/^/Template /'
echo "$ARCHIVE"
