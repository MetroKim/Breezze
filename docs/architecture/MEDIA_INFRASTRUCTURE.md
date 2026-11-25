# Breezze Media Infrastructure

Updated: 2026-11-26. This is an implementation/status contract, **not a claim that every commercial song is playable**.

## Existing deployed-system architecture (source-level)

```text
Flutter search/browse
  │
  ├─ Supabase Auth (required sign-in)
  │
  ├─ NestJS /providers/music/search
  │    ├─ Deezer catalog metadata (keyless)
  │    ├─ Spotify metadata (only with official backend credentials)
  │    └─ MusicBrainz recording metadata (opt-in, noncommercial terms)
  │
  ├─ NestJS /playback/sessions
  │    ├─ Canonical track / provider-scoped identity
  │    ├─ Territory from trusted Cloudflare edge
  │    ├─ Rights window, takedown, stream.full permission
  │    ├─ Provider-specific availability and audio source (only if licensed)
  │    └─ Owned audio variant: ready, verified, nonzero bytes
  │
  └─ Signed short-lived media grant
       └─ Cloudflare media Worker
            └─ Private R2 /audio/{id}/{quality}, /video/{id}/original.mp4
                  ├─ GET, HEAD, single byte range (206)
                  ├─ If-Range strong ETag match; stale validator -> full 200
                  ├─ If-None-Match with signed access -> private 304
                  └─ no-store, denied access for invalid/expired signatures
```

## Important constraints

* The public **Liner desktop** project is not a licensed provider API for Breezze. Do not copy private signing code, reuse core algorithms, contact protected Liner API endpoints, or add an unapproved `liner` playback adapter. Its source-available license imposes specific restrictions.
* BitChord is a GPLv3 YouTube Music Android client; its Go server is a listen-together synchronization service, not an audio catalog or distribution agreement. Do not bundle GPL code or port private YouTube extraction into Breezze.
* Spotify, Deezer, MusicBrainz and YouTube metadata alone never authorize a native full-song stream, download or lossless claim. YouTube videos remain in the official visible player.
* Separate media partners may be integrated through the existing `ProviderAdapter` interface only after acquiring explicit rights and consent for app use, territories, qualities, caching and offline storage.
* Media bearer URLs are secrets; never print them in logs, analytics, error responses or chat. Keep signing keys out of git and the Flutter binary.
* Audio requests must be backed by either a **rights-authorized provider lease** or **Breezze-owned ingested R2 bytes**, not a metadata URL.

## 2026-11-26 implementation

**Cloudflare R2 byte delivery**

* Added conditional **If-Range** support. Only a strong ETag for the exact R2 object permits `206 Partial Content`. Mismatched, weak or obsolete validators return a fresh full `200` representation to avoid corrupt resumptions.
* Added conditional **If-None-Match** handling. A `304` can be returned only after verifying the signed URL, and is `private, no-store`, without object contents.
* Existing range, HEAD, expired-signature, private-bucket, strict CORS and no-cache constraints are retained.

**NestJS media-readiness guard**

* Signed media probes now require the **exact permitted encoding**: AAC_128 / AAC_256 / download => `audio/mp4` or `audio/aac`; LOSSLESS / HI_RES => `audio/flac` or `audio/x-flac`; licensed ingested video => `video/mp4`.
* A signed link to an object with a mismatched MIME is rejected **before** the listener receives a playback grant. Provider HLS/DASH validation remains separate in `provider-stream-guard.ts`.
* Added backend and Worker regression tests and wired the MIME tests into `media-delivery-verify.yml`.

## Deployment and verification gates

1. Review GitHub Actions `media-delivery-verify.yml`: TypeScript backend typecheck, Jest rights/asset probes, Worker checks, media URL tests, local HTTP ingest/synthetic decoder validation and PostgreSQL migration tests.
2. Provision the exact Worker environment: **MEDIA_BUCKET**, **MEDIA_SIGNING_KEY** shared with the backend signer, **CDN_BASE_URL** on the backend, trusted origin/country routing. Do not publish secrets. The QA bucket is separate from production.
3. Verify real owned **licensed** audio from upload to authenticated stream to HEAD/range/seek and expiry. Validate Android/iOS background playback and locked-screen behavior with emulators.
4. Verify consent and current rights before allowing any catalog source to produce native audio or downloads.
5. Keep release and production deployment gated. A source commit or passing unit test alone does not prove production availability.

**Known unfinished work:** obtaining licensed full-track audio sources for the complete discovery catalog, operational media delivery evidence under the actual deployed credentials, and full device-level acceptance.
