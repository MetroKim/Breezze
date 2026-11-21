import re
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from ytmusicapi import YTMusic

app = FastAPI(title="Breezze YouTube Music Metadata Adapter", version="1.0.0")
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{6,64}$")


def normalize_track(item: dict[str, Any]) -> dict[str, Any] | None:
    video_id = item.get("videoId")
    title = item.get("title")
    if not isinstance(video_id, str) or not VIDEO_ID.fullmatch(video_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None

    artists = item.get("artists") or []
    artist_names = [
        artist.get("name", "").strip()
        for artist in artists
        if isinstance(artist, dict) and isinstance(artist.get("name"), str)
    ]
    thumbnails = item.get("thumbnails") or []
    artwork_url = None
    if thumbnails and isinstance(thumbnails[-1], dict):
        candidate = thumbnails[-1].get("url")
        if isinstance(candidate, str) and candidate.startswith("https://"):
            artwork_url = candidate

    raw_duration = item.get("duration_seconds")
    try:
        duration = int(raw_duration) if raw_duration is not None else None
    except (TypeError, ValueError):
        duration = None

    return {
        "providerTrackId": video_id,
        "title": title.strip(),
        "artist": ", ".join(artist_names) or "Unknown artist",
        "artworkUrl": artwork_url,
        "durationSec": duration,
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/search")
def search(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=20, ge=1, le=25),
) -> dict[str, Any]:
    try:
        results = YTMusic().search(q.strip(), filter="songs", limit=limit)
        tracks = [track for item in results if (track := normalize_track(item))]
        return {"tracks": tracks}
    except Exception as exc:
        # Do not leak provider request headers, cookies, or upstream payloads.
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc


@app.get("/tracks/{video_id}")
def get_track(video_id: str) -> dict[str, Any]:
    if not VIDEO_ID.fullmatch(video_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ID")
    try:
        song = YTMusic().get_song(video_id)
        details = song.get("videoDetails") or {}
        title = details.get("title")
        author = details.get("author")
        if not isinstance(title, str) or not isinstance(author, str):
            raise HTTPException(status_code=404, detail="TRACK_METADATA_NOT_FOUND")

        thumbnail_data = (details.get("thumbnail") or {}).get("thumbnails") or []
        artwork_url = None
        if thumbnail_data and isinstance(thumbnail_data[-1], dict):
            candidate = thumbnail_data[-1].get("url")
            if isinstance(candidate, str) and candidate.startswith("https://"):
                artwork_url = candidate

        raw_duration = details.get("lengthSeconds")
        try:
            duration = int(raw_duration) if raw_duration is not None else None
        except (TypeError, ValueError):
            duration = None

        # Intentionally discard streamingData, adaptive formats and signed URLs.
        return {
            "track": {
                "providerTrackId": video_id,
                "title": title,
                "artist": author,
                "artworkUrl": artwork_url,
                "durationSec": duration,
            }
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc
