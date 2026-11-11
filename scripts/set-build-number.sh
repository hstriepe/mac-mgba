#!/bin/bash
# Xcode build phase (both targets, after the other phases, before signing): sets the built app's
# CFBundleVersion to the commit count, `git rev-list --count HEAD`, the build number used in docs/CHAT.md
# ("--> version (BUILDNUMBER)"). As in CapturePlay's bin/build_number.sh. project.yml's
# CURRENT_PROJECT_VERSION is only the fallback outside a git checkout.
set -euo pipefail
cd "${PROJECT_DIR:?run from an Xcode build phase}"
if ! BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null)"; then
	echo "Not a git checkout: CFBundleVersion stays ${CURRENT_PROJECT_VERSION:-unchanged}"
	exit 0
fi
PLIST="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"
[ -f "$PLIST" ] || { echo "error: no Info.plist at $PLIST" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "CFBundleVersion $BUILD_NUMBER → ${INFOPLIST_PATH}"
