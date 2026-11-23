# Breezze Cloudflare media edge

This Worker is a private R2 playback gateway for Breezze-owned or separately rights-cleared catalog audio. It does not accept user uploads or ingest third-party provider streams.

## Provisioning

1. Create a private Cloudflare R2 bucket named `breezze-media`.
2. Authenticate Wrangler and set `MEDIA_SIGNING_KEY` with at least 32 random bytes using `npx wrangler secret put MEDIA_SIGNING_KEY`.
3. Deploy with `npx wrangler deploy` and attach the media hostname.
4. Configure the API signing key and CDN base URL to match the Worker.

Keep the bucket private. Never expose R2 credentials to the mobile client. Playback URLs are short-lived bearer capabilities and are returned only after the API authorizes the track's rights and territory.

## Object and request contract

- Objects use `audio/{canonicalTrackId}/{variant}`.
- The Worker accepts signed `GET` and `HEAD` requests and supports byte ranges for seeking.
- Responses are `private, no-store`; signed URLs must not enter shared caches.
- No upload, quarantine, artist-submission, or media-transcoding endpoint exists in the listener app.

Provider-hosted audio must be delivered by the approved provider directly to the client. This R2 bucket is only for Breezze-owned or explicitly rights-cleared audio. Provisioning and deployment remain account-side steps.
