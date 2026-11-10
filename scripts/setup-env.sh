#!/bin/bash
# Installs or refreshes the prerequisites (idempotent, no sudo): Homebrew tools, the submodule, libmgba, the DATs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export HOMEBREW_NO_ENV_HINTS=1
for tool in cmake ninja xcodegen; do command -v "$tool" >/dev/null || brew install "$tool"; done
git submodule update --init
scripts/build-libmgba.sh --if-needed
scripts/fetch-dats.sh || echo "warning: DATs not downloaded (offline?)"
scripts/check-env.sh
