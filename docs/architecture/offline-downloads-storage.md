# Breezze Offline Downloads, Storage and Rights Architecture

Status: implementation specification  
Scope: Flutter mobile clients first; backend entitlement and sync work follows the frontend milestone.

This specification extends the existing Breezze download flow. It does not replace the current rights-authorized download URL, owner-scoped local library, offline playback, or server-issued offline lease checks.

## 1. Product and platform rules

- Download only audio for which Breezze's rights decision explicitly grants offline use.
- Metadata/search providers (including YouTube Music metadata) are not audio download authorities.
- Never infer download rights from a playable stream URL.
- Store media and its metadata in an application-private directory. Do not put audio in a user-visible shared Documents folder by default.
- Use platform APIs to resolve the private directory. Do not hard-code iOS container paths on Flutter or other platforms.
- Keep user-created playlists, favorites, and library metadata when downloads are cleared.
- A local file is playable only when its owner matches the signed-in account and its cached rights lease is still valid.
- A missing network connection does not itself revoke a still-valid offline lease. Revalidate when online.

### Platform-specific rights

FairPlay Streaming is an Apple-platform DRM technology, not a universal Flutter DRM layer. Breezze must use a licensed DRM solution supported by each target platform and content provider (for example, FairPlay on supported Apple playback paths and the provider-approved equivalent on Android/other platforms). If a source does not authorize offline downloads or provide an approved DRM/offline-license mechanism, show “Not available for offline” and do not save its audio.

File obfuscation, renamed extensions, or encrypted metadata alone are not DRM. Do not modify media container headers and claim FairPlay compatibility. DRM enforcement must be provided by the authorized license system.

## 2. Private storage layout

Resolve the root through the platform's application-support/private storage API. Suggested logical layout:

```text
<app-private-data>/
  Breezze/
    Music/
      Downloaded/
        <track-id>_<album-id>_<quality-version>/
          audio.m4a
          lyrics.lrc                 # optional
          artwork.jpg                # optional
          metadata.json
          transfer.part              # temporary; never playable
      Thumbnails/
    Database/
      breezze.sqlite
    Preferences/
      download-settings.json         # until preferences move to Drift
  tmp/
```

The current app already stores per-track directories with `audio.m4a`, optional `cover.jpg`, `lyrics.lrc`, and `meta.json`. Migrate metadata compatibly; do not orphan existing downloads.

Filename convention for finalized audio:

```text
{track_id}_{album_id}_{version}.m4a
```

Track and album identifiers must be sanitized before becoming path components. The canonical catalog ID remains the database identity; a local storage key must not be treated as a catalog ID.

## 3. Audio quality and file integrity

- Standard target: AAC in MPEG-4 container (`.m4a`), nominal 256 kbps where the licensed source supplies it.
- Lossless target: ALAC only where the provider grants a lossless offline asset.
- Sample rates and bit depth must reflect the actual delivered asset; do not upsample and label it hi-res.
- The server/provider selects the authorized rendition. The client must not fabricate a quality variant.
- Record expected byte length, actual byte length, MIME/container information, and SHA-256 checksum when the authorized source supplies a trusted checksum.
- A download is not marked complete until the transfer is finalized and integrity checks pass.
- A partial file is never exposed to the player or listed as downloaded.

## 4. Persistent download record

Implement this as a Drift/SQLite table in the mobile database. The table is local operational state; the backend remains authoritative for entitlement and revocation.

Suggested columns:

| Column | Type | Purpose |
|---|---|---|
| id | TEXT primary key | Local download job UUID |
| track_id | TEXT | Canonical Breezze catalog track ID |
| album_id | TEXT nullable | Album association |
| user_id | TEXT | Account owner; required for isolation |
| file_path | TEXT | App-private finalized path |
| partial_path | TEXT nullable | Resumable temporary path |
| status | TEXT | State-machine status |
| progress | INTEGER | 0–100 |
| size_bytes | INTEGER nullable | Expected asset size |
| downloaded_bytes | INTEGER | Last durable byte checkpoint |
| checksum_sha256 | TEXT nullable | Expected integrity digest |
| start_time | DATETIME nullable | First transfer start |
| last_update | DATETIME | Last persisted progress |
| expires_at | DATETIME nullable | Effective offline lease expiry |
| revoked_at | DATETIME nullable | Server revocation time |
| priority | INTEGER | High=3, medium=2, low=1 |
| wifi_only | BOOLEAN | Per-job network restriction |
| quality | TEXT | Standard or lossless |
| created_at / updated_at | DATETIME | Audit timestamps |

Indexes: `track_id`, `status`, `user_id`, and unique `(user_id, track_id, quality)` where product policy allows only one asset per quality.

Store display metadata (title, artist, album, duration, artwork, genre, explicit flag, track/disc numbers, year) in local catalog tables or a versioned metadata JSON sidecar. Do not put license secrets or DRM content keys in plaintext JSON. Store only opaque license identifiers and expiry metadata in app storage; protected keys belong in the platform DRM secure subsystem.

## 5. Download state machine

Canonical states:

- `not_downloaded`
- `queued`
- `downloading`
- `paused`
- `downloaded`
- `failed`
- `corrupted`
- `expired`
- `revoked`
- `removed`

Allowed transitions:

```text
not_downloaded -> queued
queued -> downloading | paused | failed | removed
downloading -> downloaded | paused | failed | corrupted | removed
paused -> queued | downloading | removed
failed -> queued (explicit retry) | removed
downloaded -> expired | revoked | corrupted | removed
expired -> queued (only after fresh rights authorization) | removed
revoked -> removed (or queued only after a new grant)
corrupted -> queued (fresh authorized transfer) | removed
removed -> not_downloaded
```

Never transition an expired/revoked item directly to playable. Reauthorization must be performed by the backend before a new transfer or lease is accepted.

## 6. Queue, concurrency, resume and retry

- Maximum three active transfers when the platform/network permits; queue the remainder.
- Preserve explicit user priority: manually requested downloads high, playlist/album batch downloads medium, disposable previews/cache low.
- Respect Wi-Fi-only and cellular-allowed settings before starting and while scheduling queued work.
- Use HTTP byte-range resume only when the server confirms range support and the response validator (ETag/Last-Modified) still matches the partial asset.
- Persist checkpoints periodically (at least every 5% or 10 seconds) without writing to SQLite for every network chunk.
- Retry transient network/server failures at most three times with exponential backoff and jitter. Do not retry rights-denied, revoked, invalid-license, or unsupported-range failures automatically.
- On app restart, reconcile queued/downloading records with partial files and revalidate authorization before resuming.
- A user cancel changes the record to removed and deletes partial/final files immediately.
- Use deterministic job identity to prevent duplicate queue entries for the same account, track, and quality.

Progress model must expose state, percentage, downloaded/total bytes, transfer speed, ETA, start time, and last update. ETA is an estimate, not a guaranteed ±2-minute promise; smooth speed over a rolling window and show no ETA until enough samples exist.

## 7. Storage management

Storage accounting includes finalized audio, partial transfers, lyrics, artwork, database overhead, and thumbnail cache. Display actual measured file sizes; do not present fixed overhead estimates as exact usage.

Priority and cleanup policy:

| Tier | Content | Automatic cleanup |
|---|---|---|
| High | Manually pinned downloads | Never automatically delete |
| Medium | Playlist/album batch downloads | Eligible below configured critical-free-space threshold |
| Low | Temporary previews and disposable cache | First to clean under storage pressure |

User-configurable settings:

- Minimum free-space threshold: 1 GB, 2 GB, 5 GB, or 10 GB.
- Wi-Fi-only downloads.
- Allow cellular downloads.
- Automatic cleanup enabled/disabled.
- Download quality: Standard / Lossless, subject to provider rights and availability.

Use real free-space measurements where supported. The proposed 2 GB / 1 GB / 500 MB thresholds are policy defaults to tune per platform; cleanup must never delete high-priority user-pinned audio. Ask for confirmation before a destructive “remove all downloads” action.

## 8. Offline library and sync

Read path:

1. Query local database first.
2. Confirm matching account owner and local file existence.
3. Confirm status is downloaded and cached offline lease is valid.
4. If online, synchronize metadata and revalidate rights in the background.
5. If offline, allow playback only while the cached lease remains valid.
6. If no local valid asset exists, show the cloud download action or “Not available offline”.

Sync state values: `synced`, `pending`, `conflicted`, `offline`.

Use explicit record versions/revisions for conflict detection. Prefer server-authoritative rights, ownership, takedown, and revocation data. Local user preferences may use last-write-wins with a revision timestamp; local state must never override a server rights revocation.

Downloads do not automatically transfer audio bytes to a new device. On a new device, sync the library metadata and re-download after a fresh rights decision and device authorization.

## 9. License expiry and revocation

- Backend rights decision authorizes each download and returns a short-lived signed transfer URL plus an offline lease bounded by actual rights expiry.
- Offline lease duration is provider/policy controlled. Current Breezze backend uses a bounded 72-hour lease; preserve this cap unless a rights agreement explicitly allows a different value.
- Revalidate leases when the app is online and on relevant account/session changes.
- Subscription/account entitlement lapse: mark affected records expired or revoked according to the rights service; do not assume a generic subscription model because Breezze currently has a free-access product direction.
- Catalog takedown or rights withdrawal: revoke promptly when online; do not promise a universal 30-day grace period unless the license agreement requires it.
- Device limit and playback count must be enforced by the license provider, not trusted client-side counters.
- On expiry, keep or delete bytes according to provider terms; always block playback. On revocation, follow the rights service's deletion requirements.

## 10. Download manager lifecycle

```text
User requests download
  -> resolve canonical catalog track ID
  -> backend RightsDecisionService checks user, territory, device and offline grant
  -> deny with a clear reason if offline use is not permitted
  -> check free space and download settings
  -> enqueue persistent job
  -> obtain short-lived authorized transfer URL and DRM license where applicable
  -> download to .part with range resume/checkpoints
  -> verify size/checksum and finalize atomically
  -> register local asset and license metadata
  -> mark downloaded and refresh Library UI
```

A signed URL is a transport authorization, not by itself a DRM license. Do not expose it in analytics, logs, crash reports, or UI.

## 11. Cleanup and maintenance

- Low storage: clean low-priority cache first, then eligible medium-priority assets only when user policy permits.
- User cleanup: offer remove selected downloads and remove all downloads; preserve favorites, playlists, and library metadata.
- App upgrade: reconcile database schema, partial transfers, missing files, and checksums.
- Expired/revoked assets: enforce provider deletion policy; do not assume a fixed 30-day grace period.
- Temporary files: remove abandoned partial files only after checking whether a persistent job can resume.
- OS may reclaim cache/temp directories; finalized offline media must live in a durable application-private support/documents directory, not a purgeable cache directory.

## 12. Analytics

Emit privacy-minimized events:

- `download_started`: track_id, quality, wifi_only, priority
- `download_progress`: track_id, progress_bucket, speed_bucket (avoid high-frequency raw telemetry)
- `download_completed`: track_id, duration_ms, bytes
- `download_failed`: track_id, normalized_error_code, retry_count
- `download_revoked`: track_id, normalized_reason
- `download_expired`: track_id
- `download_removed`: track_id, user_initiated
- `storage_cleanup_completed`: bytes_freed, tier_counts

Do not send signed URLs, license keys, access tokens, raw local paths, or unnecessary personal data to analytics.

## 13. Frontend acceptance checklist

- [ ] Persistent queue survives app restart.
- [ ] Download state and progress are visible in Downloads.
- [ ] Progress updates at least every 5% or 10 seconds.
- [ ] ETA and speed appear only when measurable.
- [ ] Wi-Fi-only and cellular settings are persisted and enforced.
- [ ] Standard/Lossless setting maps only to provider-authorized renditions.
- [ ] Storage usage is measured from actual files.
- [ ] Free Up Space confirms destructive action and preserves playlists/library.
- [ ] Retry, pause, resume, cancel, and remove controls work.
- [ ] Offline playback works for owner-matched, unexpired, downloaded files.
- [ ] Account switching cannot expose another user's files.
- [ ] Empty, queued, downloading, failed, expired, revoked, and corrupted states have clear UI.
- [ ] Album/playlist batch downloads handle large assets and partial failures.

## 14. Backend and platform acceptance checklist

- [ ] RightsDecisionService is authoritative for every download and revalidation.
- [ ] Offline grant/lease is bounded by catalog rights and provider policy.
- [ ] Revocation and takedown invalidate leases.
- [ ] Signed URLs are short-lived and never logged.
- [ ] Byte-range resume is supported and validated by the media origin.
- [ ] Trusted checksum/length metadata is returned where available.
- [ ] DRM uses provider-approved platform implementations.
- [ ] Device limits and license renewal are server/provider enforced.
- [ ] Download records are owner-scoped and tenant-isolated.
- [ ] New-device sync transfers metadata, not unauthorized audio bytes.
- [ ] Download analytics exclude secrets and signed URLs.

## 15. Implementation order

1. Frontend: Downloads screen states, storage summary, cleanup confirmation, and persistent download preferences.
2. Frontend/data: Drift download records and migration; reconcile existing `meta.json` downloads without data loss.
3. Download engine: persistent queue, pause/cancel/retry, range resume, checkpoints, concurrency and progress.
4. Platform integration: background transfer behavior, network constraints, filesystem/free-space APIs.
5. Backend: lease/device semantics, range support, revocation sync, checksums, audit and rate controls.
6. DRM: integrate only after a licensed provider and supported platform DRM path are selected.
7. QA: restart/interruption, account-switch isolation, low-storage, expired/revoked, corrupted file, large album, and offline playback tests.
8. Production: instrumented load and reliability tests; do not claim scale or background guarantees until tested on real devices and deployed infrastructure.
