#!/bin/bash
# Regenerates the icons kept in the repository:
#   Builder/Icon/*.png                                   (scripts/make-builder-icon.swift; Icon Composer layers + full icon)
#   Builder/Assets.xcassets/AppIcon.appiconset/          (the builder's app icon, every macOS size)
#   Player/Resources/AppIcon.icns                        (the player template's icon; built apps get the game's own)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift scripts/make-builder-icon.swift

SET="Builder/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
images=""
for points in 16 32 128 256 512; do
	for scale in 1 2; do
		px=$((points * scale))
		name="icon_${points}x${points}@${scale}x.png"
		sips -z "$px" "$px" Builder/Icon/AppIcon-1024.png --out "$SET/$name" >/dev/null
		images="$images{\"idiom\":\"mac\",\"size\":\"${points}x${points}\",\"scale\":\"${scale}x\",\"filename\":\"$name\"},"
	done
done
printf '{"images":[%s],"info":{"version":1,"author":"xcode"}}\n' "${images%,}" > "$SET/Contents.json"
printf '{"info":{"version":1,"author":"xcode"}}\n' > Builder/Assets.xcassets/Contents.json

# Player template: mGBA's handheld on a transparent square.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/AppIcon.iconset" Player/Resources
sips -p 1024 1024 mgba/res/mgba-1024.png --out "$TMP/square.png" >/dev/null
for points in 16 32 128 256 512; do
	sips -z "$points" "$points" "$TMP/square.png" --out "$TMP/AppIcon.iconset/icon_${points}x${points}.png" >/dev/null
	sips -z $((points * 2)) $((points * 2)) "$TMP/square.png" --out "$TMP/AppIcon.iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns -o Player/Resources/AppIcon.icns "$TMP/AppIcon.iconset"
echo "icons written"
