# Breezze P0.2 — Audio engine feasibility and architecture decision

**Scope:** benchmark native PCM DSP potential, evaluate A/B/C and decide without changing Breezze's shipping player. This decision does **not** claim B-Spatial, AutoMix, lossless delivery or licensed audio are complete.

## Inspected baseline

- apps/mobile/lib/core/audio/just_audio_engine_adapter.dart wraps just_audio over native Android/Apple audio playback; audio_service_bridge.dart supplies OS media controls. Preserve this one live player.
- packages/audio_contracts/lib/src/audio_engine_adapter.dart has prepare/play/pause/seek/stop, volume, rate, state, position. **No public decoded PCM tap, native DSP hook, dual-voice synchronization or render callback.** The existing BAudioProcessingPolicy only gates rights/model eligibility; Automix plans a transition; CrossfadeController schedules a timer. None currently renders sample-accurate native blends.
- Only authorized, rights-cleared assets may be transformed or streamed in full; discovery metadata and previews do not grant such rights.

## Engine feasibility matrix

| Option | PCM evidence | Integration risk | Decision |
| --- | --- | --- | --- |
| **A — just_audio + audio_service** | Existing Breezze integration has no public decoded PCM access | Lowest background playback, seeking, session and queue risk; cannot support full custom DSP in current contract | **Keep A for M1 production, single global player** |
| **B — flutter_soloud 5.3.2** | Latest SoLoud API exposes realtime PCM streams, synchronous native custom sources and up to eight native custom DSP filter slots (supersedes older v7 "fork required" assumption) | Signed remote source access, seek/expiry, codec support, Android/iOS service/route behavior, power, mobile compatibility not yet verified | **First M3 isolated prototype candidate** |
| **C — owned callback engine (Oboe/AVAudioEngine, optional native Rust DSP)** | Android native audio callbacks and Apple's AVAudioSourceNode allow direct PCM rendering; native DSP can run without Dart in the callback | Native codec/DRM, maintenance, battery, platform and release complexity; no existing app integration | **Fallback if B fails real-device M3 gates** |

Sources: [Current just_audio docs](https://pub.dev/packages/just_audio), [SoLoud 5.3.2](https://pub.dev/packages/flutter_soloud/versions/5.3.2), [SoLoud native custom filter slots](https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/CustomFilterSlot-class.html), [SoLoud custom audio/PCM API](https://pub.dev/documentation/flutter_soloud/latest/flutter_soloud/SoLoud-class.html), [Android Oboe](https://developer.android.com/games/sdk/oboe/low-latency-audio), [Apple AVAudioSourceNode](https://developer.apple.com/documentation/avfaudio/avaudiosourcenode), [Breezze source](https://github.com/MetroKim/Breezze/blob/main/apps/mobile/lib/core/audio/just_audio_engine_adapter.dart).

## Executable native PCM / DSP probe (non-production)

tool/audio_engine_feasibility/pcm_native_probe.cpp uses C++17 with no dependencies, no licensed audio, no audio device, no player replacement and no audio-session interception. It blends two synthetic 48 kHz stereo float32 streams, smooths/crossfeeds and clamps samples. The hot path does not allocate or call Dart. Positive signal, silence, bound/finite samples and consumed checksum are asserted.

Compile and run: clang++ -O2 -std=c++17 -Wall -Wextra -Werror tool/audio_engine_feasibility/pcm_native_probe.cpp -o /tmp/breezze-pcm && /tmp/breezze-pcm

The probe processes **675,000 buffers of 256 frames**, representing **3,600 seconds of virtual media** with a 5,333.333 microsecond buffer period. It reports p50/p99/max **compute time**, general-purpose-host simulated deadline misses, total wall time, offline throughput and a result checksum. It fails on malformed output or <2x offline throughput. Breezze's **existing CI** runs it on Linux and macOS. Host latency is not an Android/iPhone output latency, and virtual one-hour media is **not one-hour wall-clock/device soak**.

## Final P0 decision

1. **A stays as the sole production player and media session**. No new audio dependencies, second controller or listener-visible DSP effect is introduced by this spike.
2. **B is selected for the next M3 proof**, behind the existing AudioEngineAdapter, with no general rollout until licensing, decoder, PCM, seek, dual-stream, focus, service and hardware evidence pass.
3. **C is contingency only**, if B's documented PCM/custom DSP hooks cannot meet real native needs. Native callbacks must not block, allocate or call Dart; use bounded buffers and one FFI strategy per module.
4. A high sample rate or AI enhancement cannot turn lossy source audio into lossless; only codec/source verification determines truthful labels.
5. Signed playback URLs, territory and action rights, expiry, takedown decisions and user isolation are mandatory for any future adapted engine.

## Separate M3 and release acceptance gates (OPEN)

- Test actual SoLoud 5.3.x native custom filter and streaming PCM on **Android and iPhone emulators/physical devices** using synthetic or explicitly licensed media, validate seek/signed URL expiry/rights and compatibility with the global background player.
- Perform **one wall-clock hour of audio playback** on at least one Android handset and iPhone, collecting CPU, battery, temperature, underruns, glitches, headsets, Bluetooth, interruption recovery and clock drift. Synthetic CI throughput does **not** substitute.
- Head-pose-to-audio <=20 ms end-to-end and zero underruns in a real soak before B-Spatial; AutoMix alignment +/-10 ms on 50 approved/synthetic cases; at least 20 verified codec/decoder reference files before a lossless/Hi-Res badge.
- Recheck package license/SDK and every target build before integrating SoLoud. Maintain the provider rights gate for positive full-track playback; no unlicensed media bypass.

**Definition of Done for P0 feasibility:** existing code reviewed, modern options compared and decision recorded, native PCM arithmetic benchmark executes on Linux/macOS CI, evidence links saved. M3 implementation, physical-device soak and media-rights release are intentionally *not* represented as done.
