#!/usr/bin/env bash
# Free preinstalled, unrelated hosted-runner toolchains before Android/Flutter builds.
# Never remove project files, Flutter, Android SDK components, emulator images, or caches.
set -euo pipefail

echo 'Breezze Android CI disk before cleanup:'
df -h /
echo 'Large preinstalled toolchains not required by Breezze:'
for dir in /usr/share/dotnet /opt/ghc /usr/local/share/powershell; do
  if [[ -d "$dir" ]]; then
    du -sh "$dir" || true
    sudo rm -rf -- "$dir"
  fi
done
echo 'Breezze Android CI disk after cleanup:'
df -h /
# SDK NDK, Java, Gradle, Flutter, and emulator images are intentionally retained.
free_kb=$(df -Pk / | awk 'NR==2 {print $4}')
if [[ "$free_kb" -lt 6291456 ]]; then
  echo "::error::Insufficient free disk for Android compilation (<6 GiB), aborting before APK copy" >&2
  exit 1
fi
