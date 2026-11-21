# Breezze Discovery Provider Setup

This document records the real providers used by Browse and the exact runtime configuration still required. Provider credentials belong in the backend deployment secret manager, never in Flutter, Cloudflare public variables, Git, or client-side URLs.

## Connected without credentials

| Feature | Provider | Current behavior | Limitation |
|---|---|---|---|
| Trending / Top Songs / Charts | Apple Music RSS | Territory-specific most-played songs feed, source attribution, rank and fetch timestamp | Metadata and chart display only; it does not grant Breezze full-track playback |
| New Releases | Apple Music RSS | Territory-specific new-release album feed | Published releases only; not a pre-release calendar |
| Artist discography | Apple iTunes Search API | Exact artist search followed by artist-ID album lookup | Apple catalog coverage only; not every regional/independent release |
| Song → album relationship | Apple iTunes Search API | Exact title + artist match, then uses the returned collection ID | No relationship is inferred when the exact match is absent |
| Album tracklist | Apple iTunes Search API | Collection-ID lookup and ordered track metadata | Preview URLs are short promotional samples; they are not full-track playback |

Apple's Search API describes ID-based lookups for artist albums and album tracklists. It also restricts promotional previews and artwork to promotion of store content; previews must appear near an Apple Store badge. Breezze currently opens catalog entries externally rather than embedding promotional previews.

## Requires deployment secrets

### Apple Music Daily Global Top 100

Set:
- `APPLE_MUSIC_DEVELOPER_TOKEN` — a valid Apple Music API developer JWT, stored only in the backend secret manager.

The backend requests `dailyGlobalTopCharts` for the selected storefront. Without this token, Daily Top 100 remains unavailable; Breezze does not substitute a generic most-played chart and label it daily.

### YouTube music videos

Set:
- `YOUTUBE_DATA_API_KEY`
- `YOUTUBE_OFFICIAL_CHANNEL_IDS` — comma-separated channel IDs manually reviewed and approved by Breezze.

The API search is restricted to the Music category and embeddable videos, then filtered to the approved channel allowlist. A generic YouTube search result is not automatically called an official music video. If the allowlist is empty, the endpoint remains unavailable rather than showing unverified uploads.

The app opens the video on YouTube. Breezze does not download, rehost, or relay YouTube media.

### JamBase concerts

Set:
- `JAMBASE_DATA_API_KEY`

The backend calls JamBase Data API v3 with a server-side Bearer token and User-Agent. Browse can filter by country and optional city name. The response includes event date, artist, venue, location, source event URL and a ticket URL when supplied. Event details and ticket availability can change; the UI links to the provider/event page.

JamBase requires an API key. Keep it server-side and review the selected plan's quota, rate limits, attribution requirements and commercial-use terms before production launch.

## Still requires a dedicated source or editorial workflow

| Feature | Missing dependency |
|---|---|
| Latest Songs | A source with verified track-addition timestamps; a popularity chart is not relabeled as newest additions |
| Coming Soon | A pre-release catalog with confirmed release dates, territory and status |
| City Charts | A licensed city-level chart source with documented ranking methodology; country-level charts are not city charts |
| Seasonal Collections | Breezze editorial CMS with curated collection metadata and canonical track IDs |
| Artist Spotlight | Breezze editorial CMS with approved artist selections and canonical artist records |

These are intentionally not populated from arbitrary search results. The backend does not create fake editorial records or synthetic rankings.

## Runtime configuration

Example backend environment entries (values must be supplied out-of-band):

```dotenv
APPLE_MUSIC_DEVELOPER_TOKEN=
YOUTUBE_DATA_API_KEY=
YOUTUBE_OFFICIAL_CHANNEL_IDS=
JAMBASE_DATA_API_KEY=
```

Do not add real values to this file or commit them. Configure the secrets in the backend's development/staging/production secret stores and restart the API deployment.

## Verification

- [ ] Apple RSS charts and releases return the selected storefront's feed.
- [ ] Daily Top 100 is populated only when a valid Apple Music developer token returns the `dailyGlobalTopCharts` feed.
- [ ] Apple artist search uses exact artist-name matching before opening a discography.
- [ ] Apple album tracks are loaded only from a returned collection ID.
- [ ] YouTube video results are empty until both API key and approved channel allowlist are configured.
- [ ] JamBase event data is fetched only server-side; no key is sent to the Flutter client.
- [ ] Provider attribution and outbound links remain visible.
- [ ] No catalog-only record is treated as a Breezze playback authorization.
- [ ] Missing credentials produce a clear provider-unavailable state, not fake content.
