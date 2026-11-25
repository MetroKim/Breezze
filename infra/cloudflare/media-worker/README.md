# Breezze media delivery · private Cloudflare R2 / Workers

Breezze has **one playback experience** backed by independent permitted media
pipelines. R2 contains only separately authorized Breezze-controlled recordings
and MP4 videos, **not** YouTube Music audio extracted from provider videos.

## Architecture and operational boundary

- Flutter uses a single queue and playback coordinator. Native audio obtains
  fresh session-scoped grants from `POST /playback/sessions`; licensed native
  MP4 video uses the `GET /videos/:assetId/playback` endpoint.
- NestJS/Prisma performs authenticated **territory + rights + takedown** checks,
  selects only verified media rows, and signs HMAC-SHA256 capabilities.
- Private `breezze-media` R2 is reachable only through `breezze-media` Worker
  (no public R2 bucket URL). Worker independently validates the signature,
  operation/purpose and expiry *before* reading object bytes.
- R2 serves exact objects and RFC 9110 `Range` / `HEAD`, with
  `Cache-Control: private, no-store`. No public CDN caching of bearer URLs.
- The YouTube embedded watch surface remains separate and visible; its
  metadata IDs **never** become R2 upload or audio-stream permissions.

## Delivery object keys

| Asset | Object key | Signed endpoint |
| --- | --- | --- |
| AAC audio | `audio/{canonicalUUID}/AAC_128` or `AAC_256` | `GET /audio/{uuid}/{variant}` |
| FLAC | `audio/{canonicalUUID}/LOSSLESS` or `HI_RES` | Same |
| Licensed MP4 | `video/{videoAssetUUID}/original.mp4` | `GET /video/{uuid}/stream` |
| Audio download | Existing `AAC_256` object | `GET /audio/{uuid}/download` |
| Video download | Existing MP4 object | `GET /video/{uuid}/download` |

## Privileged ingestion / readiness (no listener upload)

1. A licensed, canonical `breezze_internal` Track must already exist with
   `stream.full` (audio) and/or `video.play` (video) rights and no takedown.
2. Admin account obtains an HMAC-signed short-lived upload grant through
   `POST /admin/audio-catalog/issue-ingest` or
   `POST /admin/video-catalog/issue-ingest` (body:
   `{ "trackId": "<UUID>", "sizeBytes": 1000000 }`).
3. The operator uploads that **rights-cleared local file** with an exact
   `Content-Type` and `Content-Length` as required by the grant, using
   HTTP PUT to `/ingest/audio/...` or `/ingest/video/{assetId}`. Video
   grants support `video/mp4` and at most 95,000,000 bytes per PUT.
   Workers reject forged/missing/expired signatures, wrong sizes and
   invalid format-magic bytes. These checks are *not* malware scanning or
   full codec/transcode QA.
4. An admin invokes `POST /admin/audio-catalog/verify-asset` or
   `POST /admin/video-catalog/verify-asset` (video body:
   `{ "assetId": "<UUID>" }`). The backend performs authenticated
   authorization and signed HTTPS HEAD against the R2 Worker, then
   promotes only a present object to `ready`, recording an audit event.
5. Listener playback is granted *again* after rights/territory checks;
   the Worker never trusts arbitrary client URLs as object grants.

## Configuration

- Wrangler config: `infra/cloudflare/media-worker/wrangler.toml`, R2 binding
  `MEDIA_BUCKET` -> `breezze-media`.
- Worker **secret**: `MEDIA_SIGNING_KEY` (at least 32 random UTF-8 bytes).
- Railway backend **secret**: identical `MEDIA_SIGNING_KEY`. Backend config
  `CDN_BASE_URL` is the Worker's **HTTPS origin**, not the API Worker.
- Keep R2 private; no S3 credential, OAuth token or signing key belongs in app
  assets or public GitHub Actions logs.
- Deploy only after `npm run check && npm test` in media-worker and backend
  CI pass, both signing secrets match, and a real *licensed sample object*
  is uploaded/verified. Do not activate videos by editing database status.
- Production listener grants fail closed on missing CDN HEAD, rights, territory
  or media asset. Rotating the signing key invalidates outstanding URLs.
- Playbacks cannot claim a full YouTube Music recording merely by matching an
  external metadata identifier. No extracted YouTube media is ingested.

## Current limitations / release gates

- Max single Worker upload 95 MB. Larger audio/videos require a separate,
  rights-gated multipart ingest and transcoding pipeline.
- MP4 box signature and FLAC/AAC header checks are not full media validation.
  Add antivirus, ffprobe/transcode, SHA-256 and human review before broad ingest.
- No complete DRM, key-management or device-bound offline-license service yet.
- HMAC bearer URLs remain valid until expiry even if rights are withdrawn
  during that interval; shorten lease windows and add revocation mechanisms
  for stronger takedown SLAs.
- Provisioning does not create rights, licenses or a populated R2 catalog.
