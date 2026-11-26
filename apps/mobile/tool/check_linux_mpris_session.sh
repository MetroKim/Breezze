#!/usr/bin/env bash
# Read-only MPRIS interface probe. Run INSIDE a Linux desktop user D-Bus
# session while Breezze is open. No media commands or private data are sent.
set -euo pipefail
command -v gdbus >/dev/null || { echo 'gdbus missing' >&2; exit 2; }

# A Media Player must own org.mpris.MediaPlayer2.* in the session bus.
# Do not assume the suffix; audio_service_mpris derives its identity from
# platform configuration, which can change with plugin upgrades.
list="$(gdbus call --session --dest org.freedesktop.DBus \
  --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames)"
name="$(printf '%s' "$list" | grep -oE 'org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.-]+' \
  | grep -i 'breezze' | head -n 1 || true)"
if [[ -z "$name" ]]; then
  echo 'BREEZZE_MPRIS_NOT_REGISTERED: no session-bus player for Breezze' >&2
  exit 1
fi

xml="$(gdbus introspect --session --dest "$name" --object-path /org/mpris/MediaPlayer2)"
grep -Fq 'interface org.mpris.MediaPlayer2.Player' <<< "$xml" || {
  echo 'BREEZZE_MPRIS_PLAYER_INTERFACE_MISSING' >&2
  exit 1
}
grep -Eq 'method (Pause|PlayPause)\(' <<< "$xml" || {
  echo 'BREEZZE_MPRIS_TRANSPORT_INTERFACE_MISSING' >&2
  exit 1
}
printf 'PASS: Breezze MPRIS D-Bus player registered; transport methods exposed (%s)\n' "$name"
echo 'NOTE: registration only. Audio, actual media keys, Seek and Bluetooth still require interactive tests.'
