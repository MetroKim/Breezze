#!/usr/bin/env bash
# Start Breezze from any working directory; generate the app's Drift code and
# choose a Codespaces-safe preview when a Linux graphical session is absent.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${APP_DIR}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found on PATH." >&2
  exit 127
fi
if ! command -v dart >/dev/null 2>&1; then
  echo "Dart SDK not found on PATH. Check the Flutter SDK installation." >&2
  exit 127
fi

target="${1:-auto}"
if (( $# > 0 )); then shift; fi
if [[ "${target}" == auto ]]; then
  if [[ -n "${CODESPACES:-}" || -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    target=web
  else
    target=linux
  fi
fi

case "${target}" in
  web|web-server)
    target=web
    ;;
  linux)
    if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
      echo "No X11 or Wayland session is available. Switching to browser preview." >&2
      target=web
    fi
    ;;
  *)
    echo "Usage: bash tool/run_dev.sh [auto|web|linux] [additional flutter run flags]" >&2
    exit 2
    ;;
esac

echo "Preparing Breezze Flutter app in ${APP_DIR}"
if [[ "${target}" == linux && ! -f linux/CMakeLists.txt ]]; then
  echo "Linux runner missing; generating native platform targets."
  bash tool/generate_platform_targets.sh
fi

flutter pub get
dart run build_runner build --delete-conflicting-outputs

api_url="${BREEZZE_API_URL:-https://breezze-api-edge.ykw8vmq7ph.workers.dev}"
if [[ "${target}" == web ]]; then
  bash tool/prepare_web_database.sh
  port="${BREEZZE_PORT:-8080}"
  echo "Launching Breezze on port ${port}; open the forwarded port in Codespaces."
  exec flutter run -d web-server --web-hostname 0.0.0.0 --web-port "${port}" \
    "--dart-define=BREEZZE_API_URL=${api_url}" "$@"
fi
exec flutter run -d linux "--dart-define=BREEZZE_API_URL=${api_url}" "$@"
