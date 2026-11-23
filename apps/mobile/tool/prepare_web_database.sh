#!/usr/bin/env bash
set -euo pipefail

# Keep the WASM module and worker pinned to the same Drift release.
DRIFT_RELEASE="drift-2.35.4"
WEB_DIR="$(cd "$(dirname "$0")/.." && pwd)/web"
mkdir -p "$WEB_DIR"

curl --fail --location --silent --show-error \
  "https://github.com/simolus3/drift/releases/download/${DRIFT_RELEASE}/sqlite3.wasm" \
  --output "$WEB_DIR/sqlite3.wasm"
curl --fail --location --silent --show-error \
  "https://github.com/simolus3/drift/releases/download/${DRIFT_RELEASE}/drift_worker.js" \
  --output "$WEB_DIR/drift_worker.js"

test -s "$WEB_DIR/sqlite3.wasm"
test -s "$WEB_DIR/drift_worker.js"
