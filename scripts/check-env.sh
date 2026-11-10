#!/bin/bash
# One line per prerequisite; exit 1 when something is missing.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()   { printf '  ok    %s\n' "$1"; }
miss() { printf '  MISS  %s  →  %s\n' "$1" "$2"; fail=1; }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else miss "$1" "$3"; fi; }

check "Xcode ($(xcodebuild -version 2>/dev/null | head -1))" "xcodebuild -version" "install Xcode, xcode-select -s"
check "cmake" "command -v cmake" "brew install cmake"
check "ninja" "command -v ninja" "brew install ninja"
check "xcodegen" "command -v xcodegen" "brew install xcodegen"
check "mgba submodule" "[ -f '$ROOT/mgba/CMakeLists.txt' ]" "git submodule update --init"
check "libmgba built" "[ -f '$ROOT/build/libmgba/install/lib/libmgba.a' ]" "scripts/build-libmgba.sh"
for f in gba_bios.bin gb_bios.bin gbc_bios.bin sgb_bios.bin; do
	check "bios/$f" "[ -s '$ROOT/bios/$f' ]" "put your own dump in bios/ (games run without it)"
done
check "DATs (build/dats)" "[ -f '$ROOT/build/dats/gba.dat' ]" "scripts/fetch-dats.sh"
check "Developer ID identity" "security find-identity -v -p codesigning | grep -q 'Developer ID Application'" "ad hoc signing still works"
check "ROM library /Volumes/Shared/RETRO_GAMES/ROMs" "[ -d /Volumes/Shared/RETRO_GAMES/ROMs ]" "mount /Volumes/Shared (only a default folder)"
exit $fail
