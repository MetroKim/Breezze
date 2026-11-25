# Breezze — Google and Apple sign-in: authoritative Supabase configuration

> Current architecture: **Supabase Auth is the sign-in identity authority.**
> The existing NestJS `social-auth.service.ts` and `GOOGLE_OAUTH_*` variables describe an older, separately implemented compatibility flow. **Do not configure or enable that duplicate flow as Breezze's primary Google login.** The signed-in Flutter client uses `SupabaseAuthBridge`, and its access token is independently verified by `SupabaseExchangeService` before a transitional Breezze API session is issued.

## Current service identities

- Existing Google Cloud project from prior setup: **Breezze / `breezze-515712`** (previously recorded; live Console access was not available for re-verification on 25 November 2026). Reuse this project; do not create another.
- Supabase project: **`djwvyjtebmsavhcrmhxf`**. The project itself is active; previous setup notes record the Google provider enabled in *Testing* with basic `openid`, email and profile scopes. Those Google dashboard settings need live re-verification before production acceptance.
- Supabase Google OAuth **web** redirect URI (Google Auth Platform client used for Supabase):
  `https://djwvyjtebmsavhcrmhxf.supabase.co/auth/v1/callback`
- The `BREEZZE_SUPABASE_URL` and `BREEZZE_SUPABASE_PUBLISHABLE_KEY` are passed to Flutter at build/run time. The publishable key is public, but **never** put a Supabase service-role/secret key or a Google OAuth client secret in Flutter.
- For native Google sign-in, Flutter additionally needs the *public* `BREEZZE_GOOGLE_WEB_CLIENT_ID` and (on iOS) `BREEZZE_GOOGLE_IOS_CLIENT_ID`, passed via `--dart-define`. The current CI Android/iOS build definitions do **not** provide these, so native Google sign-in remains disabled in those artifacts until configured.

## Android native Google login — required before enabling

1. Inspect the actual generated Android application ID and stable signing certificate fingerprints (debug/emulator signing and later release/Play signing must be registered separately). `apps/mobile/tool/generate_platform_targets.sh` runs `flutter create --project-name=breezze --org=com.breezze`, so **`com.breezze.breezze` is the expected generated ID**, not a substitute for checking the final Android runner.
2. In the **existing** Google Cloud project, create or verify an Android OAuth client matching the final package ID and SHA-1 fingerprint(s). Do not fabricate SHA-1 values or rely on an ephemeral CI debug keystore as a stable production identity.
3. Keep the Web OAuth client used as `BREEZZE_GOOGLE_WEB_CLIENT_ID` registered with Supabase. Google sign-in 7.x uses this as `serverClientId` on Android. Test real account selection, returned Google ID token, `supabase.auth.signInWithIdToken` and subsequent Breezze JWT exchange on a signed emulator/device.

## iOS native Google login — required before enabling

1. Confirm the generated Xcode bundle identifier; `com.breezze.breezze` is expected unless the target has been overridden. Create/verify a matching iOS OAuth client in the existing Google Cloud project.
2. Set `BREEZZE_GOOGLE_IOS_CLIENT_ID` in the environment **when generating** the iOS runner. The existing `generate_platform_targets.sh` writes the correct reversed client-ID `CFBundleURLTypes` scheme and `GIDClientID` into the generated Info.plist. Pass the same iOS client ID to Flutter at build time.
3. Verify real iOS consent/account picker, redirect, ID-token validation by Supabase, Breezze session exchange, cancellation, account switching and sign-out. Apple Sign-In remains independently disabled until its credentials and native capability are validated.

## CI builds with verified native Google credentials

The existing GitHub Actions [Breezze Quality](../../.github/workflows/breezze-quality.yml) workflow previously omitted the native Google OAuth `--dart-define` values. It now integrates **public** Google OAuth client IDs from GitHub **Actions repository variables**. An explicit per-platform approval flag defaults off, so no unverified production/demo build suddenly exposes broken Google login.

| GitHub Actions repository variable | Meaning |
| --- | --- |
| `BREEZZE_GOOGLE_WEB_CLIENT_ID` | Existing registered Google **Web application** OAuth client ID, enabled in Supabase Google provider |

Previously configured Breezze Web OAuth client ID (public identifier; prior Google Cloud setup, pending current dashboard revalidation): `524100653326-8i401dbgt8h33fjp5qjdnjkrtnuqmdis.apps.googleusercontent.com`. GitHub native Android/iOS builds use this ID as a **fallback only when the corresponding `*_VERIFIED=true` flag is explicitly set**; an Actions repository variable overrides it if the Google Web client is rotated. This does **not** activate an unverified Android/iOS sign-in, replace the native OAuth client registration or supply server-only secrets.
| `BREEZZE_GOOGLE_IOS_CLIENT_ID` | Separate iOS OAuth client ID matching the generated iOS bundle identifier |
| `BREEZZE_GOOGLE_ANDROID_VERIFIED` | Set to `true` **only after** the Android package and the actual signed APK's SHA-1 are registered and verified in Google Cloud |
| `BREEZZE_GOOGLE_IOS_VERIFIED` | Set to `true` **only after** iOS bundle ID, OAuth client, and URL callback registration are verified |

- Android debug/release artifact builds include the Web OAuth client ID only when Android verification is explicitly approved; otherwise the build-time value is empty and Flutter hides the native Google button.
- iOS generated runner only receives the iOS client ID when iOS verification is approved. The runner script writes `GIDClientID` and reversed client-ID callback scheme to Info.plist; CI verifies both before compiling the app. The iOS build also receives both public Google client IDs.
- GitHub variables are **not** OAuth client secrets. Keep all Web client secrets exclusively in Google Cloud/Supabase encrypted provider configuration; do not add them to Actions or Flutter.
- Set `BREEZZE_GOOGLE_ANDROID_VERIFIED` and `BREEZZE_GOOGLE_IOS_VERIFIED` independently. A successful build **does not** prove the Google account picker, native signed-app SHA-1, Supabase identity exchange, consent, or emulator sign-in. Run those live tests separately, including the actual release signing identity.
- The separate YouTube read-only account connection still requires its own dedicated Web OAuth client, secret, callback, Google consent and production rights/privacy review. It is **not** enabled by these Google sign-in flags.

## Separate YouTube account playlist permission — NOT Google login

- An authenticated Breezze user may **separately opt in** to read-only YouTube Data API playlist access. This never reuses Supabase Google sign-in's token and does not authorize YouTube Music song audio or downloads.
- Backend: `YoutubeAccountService`; required private Railway environment variables: `YOUTUBE_ACCOUNT_CLIENT_ID` (dedicated Google Web OAuth client), `YOUTUBE_ACCOUNT_CLIENT_SECRET`, `YOUTUBE_ACCOUNT_REDIRECT_URI`, `YOUTUBE_ACCOUNT_TOKEN_KEY` (32-byte base64 AES-GCM key), and finally `YOUTUBE_ACCOUNT_LINK_ENABLED=true` **only after** real consent/security/production verification.
- On **25 November 2026**, the existing Railway production API was confirmed to contain the non-secret callback URI
  `https://breezze-api-production.up.railway.app/api/v1/youtube-account/callback`,
  a unique server-side encryption key and `YOUTUBE_ACCOUNT_LINK_ENABLED=false`. Variables were saved **without redeploying**; they do not prove live callback routing or account consent. The dedicated YouTube OAuth client ID/secret remain absent.
- In Google Cloud project `breezze-515712`, enable/verify **YouTube Data API v3**, configure Google Auth Platform branding/audience/privacy, add the narrow `https://www.googleapis.com/auth/youtube.readonly` scope, create a **separate Web OAuth client** with that exact Railway HTTPS callback URI, and save its secret only to Railway.
- If Google Cloud requires verification for the YouTube scope, keep the app restricted to authorized test users until approved. Never enable a public unverified grant or silently expand permissions.
- The callback can later move to a **verified Breezze-owned HTTPS domain** after that hostname is actually configured, tested and added to Google Cloud. Do not claim that `breezze.app` is routed in Cloudflare until its zone/domain is observed.

## Acceptance gates (not yet fully passed)

- [ ] Google Cloud existing project, clients, authorized redirect(s), consent and test-user configuration read back from live Console
- [ ] Android package/SHA-1 and iOS bundle/client ID verified against build signing identities
- [ ] Supabase Google provider live configuration verified, with real native login → Supabase identity → Breezze API session exchange on both platforms
- [ ] Dedicated YouTube Web OAuth client and read-only scope configured; test consent → channel → owned playlists → disconnect/revocation and cross-account isolation
- [ ] Privacy, verified-domain and any required Google OAuth/sensitive-scope checks approved before public enabling
- [ ] Deployment source SHA, callback reachability, emulator and production behavior verified

**No OAuth client secrets, token encryption keys, end-user tokens or private keys may be committed to this repository.**

References: [Supabase Google sign-in](https://supabase.com/docs/guides/auth/social-login/auth-google), [Google web-server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server), [YouTube authorization](https://developers.google.com/youtube/v3/guides/authentication), [YouTube API policies](https://developers.google.com/youtube/terms/developer-policies).
