# Breezze YouTube Music metadata adapter

This isolated service uses the MIT-licensed `ytmusicapi` Python library for public YouTube Music search and track metadata. It is **not** an audio streaming proxy.

## Endpoints

- `GET /health`
- `GET /search?q={query}&limit=20`
- `GET /tracks/{videoId}`

The service deliberately drops YouTube's `streamingData`, adaptive formats, and signed media URLs. The NestJS provider adapter reports search and metadata capabilities only; playback, downloads, and rights availability remain disabled.

## Run locally

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

The backend Compose stack starts this service at `http://ytmusicapi:8000`. The API uses `YTMUSIC_API_URL` to connect to it.

## Operational and legal constraints

`ytmusicapi` is an unofficial client that emulates YouTube Music web requests; it is not an official Google API or a guarantee of service availability. Review YouTube's applicable terms, regional requirements, and usage rights before public production use. The sidecar admits at most eight concurrent upstream requests per container replica and returns HTTP 503 with `Retry-After: 2` when full. The NestJS adapter coalesces identical in-flight searches and metadata lookups per API process, and opens a 30-second circuit after five consecutive retryable upstream failures (with a single half-open recovery probe). Redis caches successful results across API replicas. Set replica counts and provider request budgets conservatively, and add provider-specific monitoring before increasing traffic. Never put browser cookies or account credentials in this service unless separately approved and secured.

This adapter supplies discovery metadata only. It does not grant rights to stream, download, re-host, or redistribute any recording.
