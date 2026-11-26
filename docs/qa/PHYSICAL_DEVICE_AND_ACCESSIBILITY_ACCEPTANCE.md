# Breezze P0 physical-device, accessibility and OS-media acceptance

**Status:** evidence required; this document is a reproducible acceptance protocol, **not** a passing device report. **No production release or source archive** until every required gate passes on the candidate Git commit SHA.

## What each test can actually prove

| Layer | Automation | What remains manual or hosted on real devices |
| --- | --- | --- |
| Flutter widget tests | 44/48 px tap targets, labeled actions, navigation, large text | Spoken screen-reader order, real gestures, dynamic speech |
| Android emulator / iOS simulator | Native decoder, local 125s test audio, account/queue, OS integration smoke | Wired headphone unplug, actual Bluetooth routing, cell calls, AirPlay |
| Linux CI (X11 + D-Bus) | Flutter startup, MPRIS interface existence, ELF libraries, distro linker compatibility | Real session media keys, GNOME/KDE Wayland, PipeWire/PulseAudio, physical peripherals |
| Cloudflare isolated QA | Signed synthetic AAC full-file streaming, duration and near-EOF byte-range integrity | Catalog rights and territory, actual phone playback/long-run connectivity |
| Signed packages | Build and verify certificates and native metadata | Developer-controlled signing keys, notarization/store approval |

## Required target profiles, at least one each

- Android: actual Android phone with Android 14+ and a Bluetooth headset, TalkBack installed; an additional lower-API test as product supports it.
- iOS: physical iPhone running the minimum supported iOS and a current iOS, with wired/BT earbuds, and VoiceOver.
- Linux: x86_64 Ubuntu 22.04/24.04 and one each Debian/Fedora/Arch, tested in X11 and Wayland when available. Qualify ARM64 separately.
- Windows: Windows 11 laptop/desktop with SMTC and keyboard media keys.
- macOS: supported Intel or Apple Silicon desktop with media keys, Now Playing, VoiceOver and keychain.
- Web: Chrome/Firefox/Safari/Edge at supported versions, reduced-motion, zoom, keyboard, browser audio policy.

## Media fixture and authorization

Use a **Breezze-owned, generated 125-second synthetic recording** stored locally on the test device or in an isolated QA R2 bucket. Never use unauthorized YouTube/Spotify/Deezer audio in QA. For the server path, require a real approved internal track, verified asset variant and territory-specific `stream.full` grant; offline requires separate `offline.download` permission and an unexpired per-user offline lease.

### Android device procedure

1. Install a **debug/test** build for the exact candidate SHA (not a public release). Sign in with a disposable verified test account.
2. Start the authorized synthetic 125-second recording. Confirm 125s duration, seek to 100s, elapsed playback increases, and the track reaches its end naturally.
3. While playing, press Home, lock screen, change screen orientation, use the notification and headset/lock-screen controls for pause, resume, seek, previous/next. Confirm queue and playback state are consistent.
4. With audio playing on a Bluetooth headset, **physically disconnect it**. Audio must pause *before* falling back to the speaker. Reconnect: it must not resume without an explicit Play.
5. With audio **playing**, receive a real phone call: pause immediately and **auto-resume after OS audio focus returns**, only if no user pause/stop/track change intervened. Repeat while already paused (must stay paused), then pause manually during the call (must stay paused), then switch tracks during the call (must not restart old audio). Test a short call while the backend pause RPC is delayed: a late pause must never defeat resume. Siri/voice assistants and other exclusive audio-focus interruptions may have indistinguishable OS event types; record their observed behavior separately and treat unwanted restarts as release failures. Inspect `adb shell dumpsys media_session` and redacted `adb logcat`.
6. Turn on TalkBack. In sign-in, Home, Search, Library, Now Playing, queue and downloads, verify spoken labels, logical focus order, 200%+ text, 48dp touch targets, and actions without drag-only gestures.
7. Switch accounts and verify cached queues, downloads and metadata never leak between users. Sign out and confirm grants are unusable.
8. Record device model/OS **without persistent device serials**, source SHA, test time, test account ID pseudonym, expected/actual results, screenshots with redaction and operator signature.

### iOS physical device procedure

1. Install a development-signed build on an actual iPhone via Xcode/test distribution; record its candidate SHA and signing identity without private key.
2. Start the 125s original recording and seek near end. Lock the phone; use Lock Screen, Control Center and physical headset buttons.
3. Trigger a real phone/FaceTime call: playback must pause immediately, then **auto-resume after focus returns** only if it was playing before interruption and no manual pause/stop/track switch occurred. Re-test while already paused and after manually pausing mid-call (no auto-resume). A disconnected AirPods/AirPlay output must always pause **without** auto-resuming or playing on the speaker. Test Siri and other exclusive focus separately because iOS audio-session event types do not reliably identify the initiating app.
4. Enable VoiceOver and Dynamic Type. Verify semantic labels, rotor navigation, reading order, large-text clipping, accessible queue reorder alternatives and all account/streaming error messages.
5. Run Xcode Accessibility Inspector Audit on primary screens, recording unresolved findings as failures. Test VoiceOver on the physical iPhone rather than claiming simulator semantics is equivalent.
6. Document verified email/Google/Apple sign-in only for activated providers, protected Keychain tokens, logout and account switch.

### Linux desktop acceptance

- Start a release **bundle** inside a real graphical user session with Secret Service keyring and PulseAudio/PipeWire available.
- From the user's session run `bash apps/mobile/tool/check_linux_mpris_session.sh`. This checks MPRIS interface registration only.
- With original QA audio playing and `playerctl` installed, run `bash apps/mobile/tool/check_linux_mpris_transport.sh` to verify **real pause/play/PlayPause state changes** (not just interface existence). Then use hardware media keys, headset disconnect, sleep/resume and window close/minimize. Verify actual audio, playback status, pause/skip and no unauthorized route-change auto-resume.
- Current `audio_service_mpris` does **not implement the MPRIS Seek method**; do not mark Linux desktop seek-from-OS PASS until a tested replacement/extension implements it. SetPosition can work independently.
- Test package formats individually (.deb, .rpm, AppImage, Flatpak, Snap and portable bundle). On sandboxed builds retest desktop portals, credential keyrings, R2 HTTPS, media permissions, MPRIS and libmpv codecs. Alpine/musl requires a separately validated runtime; do not describe a glibc bundle as universally compatible.

### Windows/macOS

- Windows: verify taskbar and native SMTC transport controls on real Windows hardware, sleep/wake, media keys, file associations, keyring, high DPI, keyboard focus, NVDA. Sign Windows packages with an authorized code-signing certificate; CI debug binaries are not signed release evidence.
- macOS: verify Now Playing, audio route switching, media keys, Keychain and sandbox file picker, VoiceOver and reduced motion. Codesign/notarize with the owner's Apple team and verify the notarization ticket. A `--no-codesign` build cannot pass production-signing acceptance.

## Evidence required for a PASS

For **each** target/OS profile: `git_sha`, exact test case, app version/build ID, physical/simulator designation, OS release, CPU arch, observed output/behavior, required screenshot/log (redacted), tester/date, explicit result PASS/FAIL/BLOCKED, and issue or retest link for any failure. A CI status of queued, cancelled or timed out is never PASS. The V8 mock call-resume tests validate *controller sequencing*, not telephony permission/focus events on real Android/iOS hardware. The Linux transport script verifies MPRIS state changes only while an authorized track is playing; it does not certify hardware keys, waveform, `Seek` support or physical Bluetooth.

The release gate closes only if (1) the same SHA passes code/build/unit/CI, (2) all required physical and accessibility acceptance evidence exists, (3) signed package verification passes, (4) rights/licensing approval exists for offered tracks/territories and offline rights, and (5) the owner explicitly lifts the freeze.

References: [Flutter accessibility tests](https://docs.flutter.dev/ui/accessibility/accessibility-testing), [audio_service_mpris capabilities](https://pub.dev/documentation/audio_service_mpris/latest/), [Flutter supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms).
