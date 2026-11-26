#!/usr/bin/env bash
# Interactive ACCEPTANCE check, not an interface-only smoke test.
#
# Requirements: a real Linux user D-Bus session, playerctl, and a Breezze
# authorized/local recording actively playing with >30 seconds remaining.
# No media metadata, track title, URL, account identity or secrets are printed.
# Run: bash apps/mobile/tool/check_linux_mpris_transport.sh
set -euo pipefail

command -v playerctl >/dev/null || {
  echo 'MPRIS_TRANSPORT_BLOCKED: install playerctl' >&2
  exit 2
}
player="$(playerctl --list-all | grep -i '^breezze' | head -n 1 || true)"
if [[ -z "$player" ]]; then
  echo 'MPRIS_TRANSPORT_BLOCKED: Breezze player not registered' >&2
  exit 1
fi

status() { playerctl --player="$player" status 2>/dev/null || true; }
wait_for_state() {
  local expected="$1"
  for _ in $(seq 1 20); do
    if [[ "$(status)" == "$expected" ]]; then return 0; fi
    sleep 0.2
  done
  echo "MPRIS_TRANSPORT_FAILED: expected $expected, received $(status)" >&2
  exit 1
}

if [[ "$(status)" != 'Playing' ]]; then
  echo 'MPRIS_TRANSPORT_BLOCKED: start authorized local audio before testing' >&2
  exit 2
fi

# After the first pause, keep a best-effort cleanup so the operator's
# original playing state is restored even if an assertion fails.
restore() { playerctl --player="$player" play >/dev/null 2>&1 || true; }
trap restore EXIT
playerctl --player="$player" pause
wait_for_state Paused
playerctl --player="$player" play
wait_for_state Playing
playerctl --player="$player" play-pause
wait_for_state Paused
playerctl --player="$player" play-pause
wait_for_state Playing
trap - EXIT

echo 'PASS: real Breezze MPRIS Pause, Play and PlayPause state changes'
echo 'NOT TESTED: physical media keys, audio waveform, Next, Previous, Seek, headsets or lock screen'
