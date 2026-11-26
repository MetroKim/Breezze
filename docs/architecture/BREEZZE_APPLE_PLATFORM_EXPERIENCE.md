# Breezze Apple-inspired experience & platform architecture

**Decision:** 2026-11-26 • **Status:** Implemented baseline, acceptance tests pending  
**Applies to:** Flutter on iOS / Android / desktop; Breezze mobile's existing code

## Product contract: Apple philosophy, Breezze identity

Breezze is an independent, listener-first music client. Adopt Apple's **clarity, hierarchy, consistent navigation, content-first composition, motion discipline and resilient media sessions** without copying Apple assets, proprietary Apple Music source code, private endpoints or protected visual trademarks.

- Preserve the original Breezze B-note artwork, four destinations **Home / Browse / Library / Search**, universal mini-player, and global Now Playing / queue authority.
- Preserve Breezze light and OLED black color tokens, existing Liquid Glass-inspired control capsules, dynamic cover-art backdrop, text styles and icon pack.
- On iOS use platform-native navigation gestures, fullscreen modal presentations and action sheets where they improve recognition. Android/desktop retain their platform conventions. Do **not** attempt to replicate Apple's private Liquid Glass renderer inside Flutter.
- Keep music metadata / artist pages legally attributable. Provider metadata does **not** grant playable Spotify or YouTube Music audio or unauthorized offline downloads.

### Official references

1. [Apple Human Interface Guidelines — Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles): craft, clarity, familiar controls and meaningful hierarchy.
2. [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): stable and predictable destinations.
3. [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass): navigation/control chrome sits above content rather than glass used indiscriminately on content.
4. [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) / [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): Dynamic Type, understandable labels, contrast, keyboard and assistive technology, Reduce Motion.
5. [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) and [handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions): activate when playing and gracefully pause for calls and route changes.
6. [Flutter CupertinoPageRoute](https://api.flutter.dev/flutter/cupertino/CupertinoPageRoute-class.html) and [audio_session](https://pub.dev/packages/audio_session): cross-platform implementation mechanisms, not Apple-private APIs.

## Layers and implementation map

| Layer | Responsibility | Authoritative files | Guardrail |
| --- | --- | --- | --- |
| **Experience policy** | Platform route transitions, iOS back gestures and full-screen details; no animation for OS Reduce Motion | `apps/mobile/lib/app/breezze_navigation.dart` | Use `breezzePageRoute` for details, never reimplement a page transition in every feature |
| **Navigation chrome** | Four persistent tabs, adaptive sidebar, mini-player above tab bar, iOS haptic selection, accessible selected state and scalable labels | `apps/mobile/lib/widgets/bz_shell.dart` | Do not add a fifth tab or a provider shelf. Preserve page state on tab switching |
| **Now Playing presentation** | Media-led typography, artwork, queue, lyrics, seek and action menus. Cupertino action sheet on iOS, Breezze material sheet elsewhere | `features/player/now_playing_screen.dart`; `widgets/bz_transport_controls.dart` | UI passes events to player controller; does not instantiate players or resolve streams |
| **Design foundation** | Semantic dark/light tokens, rounded glass control chrome, solid high-contrast fallbacks, reduced motion | `packages/design_system/lib/src/` | Blur applies to chrome, not to all artwork, cards or modals. Never import proprietary Apple fonts/logos |
| **Playback authority** | Canonical queue, player state, seek, recovery, rights-aware source resolution | `features/player/player_controller.dart` and audio contracts | Exactly ONE queue and PlayerController per signed-in session |
| **Audio engine / OS session** | AVFoundation via just_audio on iOS; ExoPlayer on Android; music-session configuration, native focus, interruption and headphones removed | `core/audio/just_audio_engine_adapter.dart` | Setup completes before first source; let just_audio activate at playback; **do not auto-resume after a call** |
| **Lock screen / notifications** | State mirroring and OS remote commands via audio_service; queue and position from controller | `core/audio/audio_service_bridge.dart` + `background_audio.dart` | Bridge never owns an independent queue/engine. Cleared when account/player ends |
| **Identity / data / policy** | Supabase required sign-in, API authorization, Supabase Postgres data, Cloudflare/R2 authorized delivery, provider metadata | Existing auth, API, media workers | No change to credentials, media grants or database schema for interface adoption |

### UI details implemented in this phase

**Adaptive transport:** The main transport capsule prioritizes Previous / Play–Pause / Next. Shuffle and Repeat remain inside the original glass capsule on ordinary widths; they move into a second accessible row on narrow screens or large Dynamic Type. Primary actions stay reachable without horizontal overflow. Playback state never duplicates.

**Cross-platform routes:** Every updated Home, Browse, Library, Search, Settings and artist/detail navigation call uses the shared route policy. On iOS a normal detail route supports the familiar edge-swipe back gesture. A fullscreen Now Playing presentation uses the **native modal transition**, whose iOS full-screen-dialog form deliberately does **not** offer an edge back-swipe; the visible Close control remains. Other platforms retain Material routes. OS Reduce Motion disables decorative page transitions.

**Contextual actions:** Now Playing's overflow menu renders as a native Cupertino action sheet only on iOS, but both platforms dispatch identical Shuffle, Repeat, Lyrics and Queue actions to the same controller. It is not a second player or an independent state machine.

**System audio:** The just_audio player wrapper prevents the plugin's default automatic interruption resumption; Breezze pauses on interruptions and noisy/headphone/Bluetooth disconnect and waits for an explicit subsequent play command. Native music session setup is awaited before first source preparation and bounded to avoid indefinite startup stalls. The underlying plugin still activates the OS audio session only when actual playback starts, consistent with Apple. The generator's iOS Runner Info.plist still has `UIBackgroundModes: audio`; no checked-in secrets, new app ID or unnecessary entitlements were added.

**Original artwork:** Spotify artist portraits and album covers render with `BoxFit.cover` inside Breezze's existing rounded artwork geometry. This is visual polish only; upstream Spotify/Deezer catalog identity and playback restrictions remain unchanged.

## Verification / release quality gates

| Area | Required evidence | Current conclusion |
| --- | --- | --- |
| Flutter static analysis, compilation and tests | `flutter analyze` + `flutter test` including platform route and adaptive transport tests | **Pending CI**; no local Flutter SDK available |
| Apple iOS simulator | iOS native push/back, fullscreen player modal close, contextual action sheet, Dynamic Type, VoiceOver and reduced motion | **Unverified** |
| OS media lifecycle | Lock screen metadata and controls; calls interrupted; headphones unplug; Bluetooth route disconnect; manual resume; focus denial; app background | **Unverified on simulator / device** |
| Android/Desktop regressions | Material route, action sheet, scoped mini-player, track seek, keyboard controls | **Unverified** |
| Accessibility | Contrast, keyboard, VoiceOver/TalkBack, 200% text scaling, 320dp responsive, high contrast | **Partially automated; full audit open** |
| Partner rights & distribution | Apple account signing, Apple Developer program, metadata attribution, Spotify/Deezer/YouTube/artist rights | **No claim of approval** |

### Next upgrades (not misrepresented as already shipped)

- Full iPhone, iPad and Mac window-size snapshots and responsive UX acceptance.
- iOS native system testing for AirPlay output routes, Bluetooth devices, interruption callbacks and Apple Music-inspired remote controls; do not claim CarPlay or AirPlay routing certified without actual device and entitlement checks.
- Optional account-scoped per-tab navigation restoration and scroll-to-top when reselecting a tab, after verifying all four page scroll controllers.
- Dynamic Type and VoiceOver audits of dialogs, playlist editing, queue drag-and-drop and authentication at realistic device sizes.
- App Store Connect / signing / privacy manifests and the provider-rights gates before production release.

**Outcome definition:** The result must feel coherent with Apple's interaction conventions *while remaining unmistakably Breezze*. A source commit alone is not a tested release.
