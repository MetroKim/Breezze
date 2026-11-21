# Breezze Cloudflare media edge

This Worker is the private R2 media gateway for Breezze. It supports:

- HMAC-signed, expiring playback URLs at `/audio/{trackId}/{variant}`.
- Short-lived, size-bound upload URLs at `/upload/{userId}/{jobId}/{filename}`.
- Private quarantine uploads into R2 and byte-range playback for seeking.
- No public R2 bucket or public object URLs.

## Provisioning

1. Create a Cloudflare R2 bucket named `breezze-media`.
2. Install Wrangler and authenticate: `npx wrangler login`.
3. From this directory, set the same random signing secret used by the NestJS API:
   `npx wrangler secret put MEDIA_SIGNING_KEY`.
   Use at least 32 random bytes. Do not commit it or put it in a frontend build.
4. Deploy: `npx wrangler deploy`.
5. Attach a custom domain such as `media.breezze.app` to the Worker route in Cloudflare.
6. Set the API `CDN_BASE_URL=https://media.breezze.app` and the same `MEDIA_SIGNING_KEY`.
7. Configure the backend media worker with `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, and `R2_BUCKET_NAME=breezze-media`. Create an R2 API token scoped to this bucket only. Keep these credentials in the worker runtime secret store, never in Flutter or the Worker bundle.
8. Copy `backend/api/.env.example` into the backend's private environment configuration and populate the values. The Worker signing secret and API signing key must match exactly.

The R2 bucket must remain private. Do not enable public bucket access or expose R2 S3 credentials to mobile clients.

## Object contract

- Uploads are written to `quarantine/{userId}/{jobId}/{filename}`.
- The media processing worker must validate, scan and transcode the quarantined object before publishing.
- Published playback objects use `audio/{canonicalTrackId}/{variant}`, where variant matches the signed playback URL.
- The API must authorize territory and rights before it issues a playback URL.

## Operational notes

Playback GET responses are cacheable for at most 60 seconds; byte-range responses are not cached. The signature expiry is checked on every Worker request. Uploads are limited to 100 MiB and the exact registered Content-Length. Configure Cloudflare WAF/rate limits on the custom domain and monitor R2 request/egress costs.

This Worker is an edge gateway, not a media transcoder or rights-management system. Production release still requires a real ingestion/transcoding pipeline, malware/content validation, a retention policy for quarantine objects, and an operational licence-revocation policy. Deploying the Worker and provisioning the bucket/domain are account-side steps and cannot be completed from this repository alone.
