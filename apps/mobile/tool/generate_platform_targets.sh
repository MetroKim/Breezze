#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter and add it to PATH." >&2
  exit 1
fi

cd "${APP_DIR}"

# Generate the native runner shells around Breezze's single lib/ codebase.
# Existing Dart source is retained; dependency resolution is intentionally
# left to the caller so this script does not silently update lockfiles.
flutter create \
  --platforms=android,ios,web,linux,macos,windows \
  --project-name=breezze \
  --org=com.breezze \
  --no-pub \
  .
