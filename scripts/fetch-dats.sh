#!/bin/bash
# Downloads the No-Intro DATs for GB, GBC and GBA from libretro-database (metadat/no-intro) into build/dats/,
# named gb.dat, gbc.dat, gba.dat. The builder bundles them to name ROMs by CRC32 (the name finds the box art).
# Rerun to refresh; without network the builder still works (it then names games after the ROM file).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/dats"
BASE="https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro"
mkdir -p "$OUT"
for pair in "gb:Nintendo%20-%20Game%20Boy" "gbc:Nintendo%20-%20Game%20Boy%20Color" "gba:Nintendo%20-%20Game%20Boy%20Advance"; do
	id="${pair%%:*}"
	name="${pair#*:}"
	curl -fsSL --retry 2 -o "$OUT/$id.dat.part" "$BASE/$name.dat"
	mv "$OUT/$id.dat.part" "$OUT/$id.dat"
	echo "$id.dat: $(grep -c 'crc ' "$OUT/$id.dat") ROMs"
done
