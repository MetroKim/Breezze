import os
import re
from datetime import datetime, timezone
from urllib.parse import parse_qs, urlsplit
from threading import BoundedSemaphore
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from ytmusicapi import YTMusic

app = FastAPI(title="Breezze YouTube Music Metadata Adapter", version="1.0.0")
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{6,64}$")
# Each container replica admits at most eight simultaneous upstream requests.
# Extra work is rejected quickly so the FastAPI thread pool cannot be exhausted.
PROVIDER_SLOTS = BoundedSemaphore(8)


def normalize_track(item: Any) -> dict[str, Any] | None:
    # Skip one malformed upstream record rather than failing the whole search.
    if not isinstance(item, dict):
        return None
    video_id = item.get("videoId")
    title = item.get("title")
    if not isinstance(video_id, str) or not VIDEO_ID.fullmatch(video_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None

    artists = item.get("artists")
    if not isinstance(artists, list):
        artists = []
    artist_names = [
        artist.get("name", "").strip()
        for artist in artists
        if isinstance(artist, dict) and isinstance(artist.get("name"), str)
    ]
    thumbnails = item.get("thumbnails")
    if not isinstance(thumbnails, list):
        thumbnails = []
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
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="YTMUSIC_CAPACITY_EXCEEDED",
            headers={"Retry-After": "2"},
        )
    try:
        results = YTMusic().search(q.strip(), filter="songs", limit=limit)
        if not isinstance(results, list):
            raise ValueError("Unexpected YouTube Music song search response")
        tracks = [track for item in results if (track := normalize_track(item))]
        return {"tracks": tracks}
    except Exception as exc:
        # Do not leak provider request headers, cookies, or upstream payloads.
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()



def normalize_video(item: Any) -> dict[str, Any] | None:
    if not isinstance(item, dict):
        return None
    video_id = item.get("videoId")
    title = item.get("title")
    video_type = item.get("videoType")
    # YouTube Music distinguishes original music videos from user uploads.
    # Do not present UGC or audio-with-static-artwork as an official video.
    if video_type != "MUSIC_VIDEO_TYPE_OMV":
        return None
    if not isinstance(video_id, str) or not VIDEO_ID.fullmatch(video_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None

    artists = item.get("artists")
    if not isinstance(artists, list):
        artists = []
    artist_names = [
        artist.get("name", "").strip()
        for artist in artists
        if isinstance(artist, dict) and isinstance(artist.get("name"), str)
    ]
    thumbnails = item.get("thumbnails")
    if not isinstance(thumbnails, list):
        thumbnails = []
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
        "videoId": video_id,
        "title": title.strip(),
        "artist": ", ".join(artist_names) or "Unknown artist",
        "artworkUrl": artwork_url,
        "durationSec": duration,
        "videoType": "MUSIC_VIDEO_TYPE_OMV",
        "classification": "youtube_music_original_music_video",
        "url": f"https://www.youtube.com/watch?v={video_id}",
    }

@app.get("/videos")
def search_videos(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=20, ge=1, le=25),
) -> dict[str, Any]:
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="YTMUSIC_CAPACITY_EXCEEDED",
            headers={"Retry-After": "2"},
        )
    try:
        results = YTMusic().search(q.strip(), filter="videos", limit=limit)
        if not isinstance(results, list):
            raise ValueError("Unexpected YouTube Music video search response")
        videos = [video for item in results if (video := normalize_video(item))]
        return {
            "source": "YouTube Music via ytmusicapi",
            "classification": "Only MUSIC_VIDEO_TYPE_OMV results are returned",
            "videos": videos,
        }
    except Exception as exc:
        # Do not leak provider request headers, cookies, or upstream payloads.
        raise HTTPException(status_code=502, detail="YTMUSIC_VIDEO_SEARCH_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()


@app.get("/tracks/{video_id}")
def get_track(video_id: str) -> dict[str, Any]:
    if not VIDEO_ID.fullmatch(video_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ID")
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="YTMUSIC_CAPACITY_EXCEEDED",
            headers={"Retry-After": "2"},
        )
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
    finally:
        PROVIDER_SLOTS.release()


# Isolated feasibility experiment: accepts only direct HTTPS audio URLs that
# the unofficial API already returns. Never deciphers signatures, bypasses DRM,
# caches audio, or offers a download. Disabled on production deployments.
def select_audio_candidate(song: dict[str, Any]) -> dict[str, Any] | None:
    if (song.get("playabilityStatus") or {}).get("status") != "OK":
        return None
    streaming = song.get("streamingData") or {}
    formats = streaming.get("adaptiveFormats") or []
    now = int(datetime.now(timezone.utc).timestamp())
    candidates = []
    for item in formats if isinstance(formats, list) else []:
        if not isinstance(item, dict):
            continue
        mime = item.get("mimeType")
        url = item.get("url")
        if not isinstance(mime, str) or not mime.startswith("audio/"):
            continue
        if not isinstance(url, str):
            continue
        try:
            parsed = urlsplit(url)
            host = (parsed.hostname or "").lower()
            expiry = int(parse_qs(parsed.query).get("expire", ["0"])[0])
        except (ValueError, TypeError):
            continue
        if parsed.scheme != "https" or not (
            host == "googlevideo.com" or host.endswith(".googlevideo.com")
        ) or parsed.username or parsed.password or expiry <= now + 60:
            continue
        bitrate = item.get("bitrate")
        if not isinstance(bitrate, int) or bitrate <= 0:
            continue
        # Keep the URL transient. Other upstream keys may contain cookies,
        # signature ciphers, identifiers or player internals: never forward.
        candidates.append({
            "streamUrl": url,
            "mimeType": mime.split(";", 1)[0],
            "bitrateKbps": bitrate // 1000,
            "expiresAt": datetime.fromtimestamp(expiry, tz=timezone.utc).isoformat(),
        })
    if not candidates:
        return None
    return max(candidates, key=lambda candidate: candidate["bitrateKbps"])


@app.get("/tracks/{video_id}/audio-candidate")
def get_audio_candidate(video_id: str) -> dict[str, Any]:
    # A native-audio POC can only run in an explicitly opted-in, non-production
    # environment. A public metadata catalog must never expose signed URLs.
    if (os.getenv("BREEZZE_YTMUSIC_AUDIO_EXPERIMENT") != "true" or
            os.getenv("RAILWAY_ENVIRONMENT_NAME", "").lower() == "production"):
        raise HTTPException(status_code=404, detail="EXPERIMENT_DISABLED")
    if not WATCH_VIDEO_ID.fullmatch(video_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ID")
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(status_code=503, detail="YTMUSIC_CAPACITY_EXCEEDED",
                            headers={"Retry-After": "2"})
    try:
        candidate = select_audio_candidate(YTMusic().get_song(video_id))
        if candidate is None:
            raise HTTPException(status_code=404, detail="DIRECT_AUDIO_NOT_AVAILABLE")
        return {"source": "youtube_music", "providerTrackId": video_id,
                "experimental": True, "candidate": candidate}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_AUDIO_PROBE_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()


@app.get("/tracks/{video_id}/music-video")
def music_video_counterpart(video_id: str) -> dict[str, Any]:
    if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ID")
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(status_code=503, detail="YTMUSIC_CAPACITY_EXCEEDED")
    try:
        playlist = YTMusic().get_watch_playlist(videoId=video_id, limit=1)
        for track in playlist.get("tracks") or []:
            if not isinstance(track, dict) or track.get("videoId") != video_id:
                continue
            counterpart = track.get("counterpart")
            if isinstance(counterpart, dict) and counterpart.get("videoType") == "MUSIC_VIDEO_TYPE_OMV":
                candidate = counterpart.get("videoId")
                if isinstance(candidate, str) and re.fullmatch(r"[A-Za-z0-9_-]{11}", candidate):
                    return {"videoId": candidate}
        return {"videoId": None}
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()



# Public YouTube Music discovery extensions. All data is metadata only:
# these endpoints never return audio URLs, cookies, or playback entitlements.
ARTIST_ID = re.compile(r"^[A-Za-z0-9_-]{10,64}$")


def _safe_artwork(item: dict[str, Any]) -> str | None:
    thumbnails = item.get("thumbnails") or []
    if not isinstance(thumbnails, list):
        return None
    for thumb in reversed(thumbnails):
        if isinstance(thumb, dict):
            url = thumb.get("url")
            if isinstance(url, str) and url.startswith("https://"):
                return url
    return None


def _normal_artist(item: dict[str, Any]) -> dict[str, Any] | None:
    artist_id = item.get("browseId")
    title = item.get("artist") or item.get("title") or item.get("name")
    if not isinstance(artist_id, str) or not ARTIST_ID.fullmatch(artist_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None
    rank = item.get("rank")
    return {
        "artistId": artist_id,
        "name": title.strip(),
        "artworkUrl": _safe_artwork(item),
        "subscribers": item.get("subscribers") if isinstance(item.get("subscribers"), str) else None,
        "rank": rank if isinstance(rank, (str, int)) and not isinstance(rank, bool) else None,
    }


@app.get("/artists/search")
def search_artists(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=20, ge=1, le=25),
) -> dict[str, Any]:
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(status_code=503, detail="YTMUSIC_CAPACITY_EXCEEDED", headers={"Retry-After": "2"})
    try:
        results = YTMusic().search(q.strip(), filter="artists", limit=limit)
        artists = [artist for item in results if isinstance(item, dict) if (artist := _normal_artist(item))]
        return {"source": "youtube_music", "artists": artists}
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()


@app.get("/artists/{artist_id}")
def get_artist(artist_id: str) -> dict[str, Any]:
    if not ARTIST_ID.fullmatch(artist_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ARTIST_ID")
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(status_code=503, detail="YTMUSIC_CAPACITY_EXCEEDED", headers={"Retry-After": "2"})
    try:
        raw = YTMusic().get_artist(artist_id)
        if not isinstance(raw, dict) or not isinstance(raw.get("name"), str):
            raise HTTPException(status_code=404, detail="ARTIST_METADATA_NOT_FOUND")
        songs = ((raw.get("songs") or {}).get("results") or [])[:20]
        albums = ((raw.get("albums") or {}).get("results") or [])[:20]
        artist = {
            "artistId": artist_id,
            "name": raw["name"].strip(),
            "description": (raw.get("description") or "")[:3000] if isinstance(raw.get("description"), str) else None,
            "artworkUrl": _safe_artwork(raw),
            "subscribers": raw.get("subscribers") if isinstance(raw.get("subscribers"), str) else None,
            "topSongs": [
                {"providerTrackId": row["videoId"], "title": row["title"], "artworkUrl": _safe_artwork(row)}
                for row in songs if isinstance(row, dict) and isinstance(row.get("title"), str)
                and isinstance(row.get("videoId"), str) and VIDEO_ID.fullmatch(row["videoId"])
            ],
            "albums": [
                {"browseId": row["browseId"], "title": row["title"], "year": row.get("year"),
                 "artworkUrl": _safe_artwork(row)}
                for row in albums if isinstance(row, dict) and isinstance(row.get("title"), str)
                and isinstance(row.get("browseId"), str) and ARTIST_ID.fullmatch(row["browseId"])
            ],
        }
        return {"source": "youtube_music", "artist": artist}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()


@app.get("/charts")
def get_charts(country: str = Query(default="ZZ", pattern=r"^[A-Z]{2}$")) -> dict[str, Any]:
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(status_code=503, detail="YTMUSIC_CAPACITY_EXCEEDED", headers={"Retry-After": "2"})
    try:
        result = YTMusic().get_charts(country=country)
        artists = [artist for row in (result.get("artists") or [])
                   if isinstance(row, dict) if (artist := _normal_artist(row))]
        playlists = []
        for row in result.get("videos") or []:
            if not isinstance(row, dict):
                continue
            playlist_id, title = row.get("playlistId"), row.get("title")
            if isinstance(playlist_id, str) and ARTIST_ID.fullmatch(playlist_id) and isinstance(title, str):
                playlists.append({"playlistId": playlist_id, "title": title, "artworkUrl": _safe_artwork(row)})
        return {
            "source": "youtube_music",
            "country": country,
            "artists": artists,
            "musicVideoPlaylists": playlists,
            # Unauthenticated get_charts does not promise Top Songs ranks.
            "songRankingAvailable": False,
        }
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_CHARTS_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()


# YouTube Music's watch queue is useful for discovery and recommendations.
# It is NOT a playable audio queue and must not contain provider media URLs.
WATCH_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


def _watch_duration(value: Any) -> int | None:
    if isinstance(value, int) and value >= 0:
        return value
    if not isinstance(value, str):
        return None
    segments = value.split(":")
    if not 1 <= len(segments) <= 3 or any(not part.isdigit() for part in segments):
        return None
    seconds = 0
    for part in segments:
        seconds = seconds * 60 + int(part)
    return seconds if seconds < 24 * 60 * 60 else None


def normalize_watch_item(item: dict[str, Any]) -> dict[str, Any] | None:
    video_id, title = item.get("videoId"), item.get("title")
    if not isinstance(video_id, str) or not WATCH_VIDEO_ID.fullmatch(video_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None
    artists = item.get("artists") or []
    artist_names = [
        artist["name"].strip() for artist in artists
        if isinstance(artist, dict) and isinstance(artist.get("name"), str)
        and artist["name"].strip()
    ] if isinstance(artists, list) else []
    thumbs = item.get("thumbnail") or item.get("thumbnails") or []
    artwork = _safe_artwork({"thumbnails": thumbs})
    return {
        "providerTrackId": video_id,
        "title": title.strip(),
        "artist": ", ".join(artist_names) or "Unknown artist",
        "artworkUrl": artwork,
        "durationSec": _watch_duration(item.get("length") or item.get("duration_seconds")),
    }


@app.get("/watch-queue/{video_id}")
def get_watch_queue(
    video_id: str,
    limit: int = Query(default=20, ge=1, le=25),
) -> dict[str, Any]:
    if not WATCH_VIDEO_ID.fullmatch(video_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ID")
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="YTMUSIC_CAPACITY_EXCEEDED",
            headers={"Retry-After": "2"},
        )
    try:
        raw = YTMusic().get_watch_playlist(videoId=video_id, limit=limit)
        if not isinstance(raw, dict) or not isinstance(raw.get("tracks"), list):
            raise HTTPException(status_code=502, detail="YTMUSIC_INVALID_WATCH_QUEUE")
        tracks = [
            track for item in raw["tracks"][:limit]
            if isinstance(item, dict) and (track := normalize_watch_item(item))
        ]
        playlist_id = raw.get("playlistId")
        return {
            "source": "youtube_music",
            "seedVideoId": video_id,
            "playlistId": playlist_id if isinstance(playlist_id, str) else None,
            "tracks": tracks,
            "playbackAvailable": False,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail="YTMUSIC_WATCH_QUEUE_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()


# Public unauthenticated catalog surfaces. All external fields are normalized
# to bounded metadata; never expose provider cookies, signed media URLs, raw
# upstream payloads, account-library data or third-party entitlements.
PLAYLIST_ID = re.compile(r"^[A-Za-z0-9_-]{10,128}$")
MOOD_PARAMS = re.compile(r"^[A-Za-z0-9_-]{6,256}$")
ALBUM_ID = re.compile(r"^MPRE[A-Za-z0-9_-]{6,60}$")


def _catalog_call(action: Any) -> dict[str, Any]:
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(
            status_code=503, detail="YTMUSIC_CAPACITY_EXCEEDED",
            headers={"Retry-After": "2"},
        )
    try:
        return action()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=502, detail="YTMUSIC_CATALOG_UPSTREAM_UNAVAILABLE"
        ) from exc
    finally:
        PROVIDER_SLOTS.release()


def _catalog_artist_names(raw: Any) -> list[str]:
    if not isinstance(raw, list):
        return []
    return [
        item["name"].strip()
        for item in raw[:12]
        if isinstance(item, dict) and isinstance(item.get("name"), str)
        and item["name"].strip()
    ]


def _catalog_track(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    entry = normalize_watch_item(raw)
    if entry is None:
        return None
    duration = raw.get("duration_seconds")
    if isinstance(duration, (int, float)) and 0 <= duration < 86400:
        entry["durationSec"] = int(duration)
    entry["isExplicit"] = raw.get("isExplicit") is True
    entry["isAvailable"] = raw.get("isAvailable") is not False
    return entry


def _catalog_playlist(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    playlist_id, title = raw.get("playlistId"), raw.get("title")
    if not isinstance(playlist_id, str) or not PLAYLIST_ID.fullmatch(playlist_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None
    return {
        "playlistId": playlist_id,
        "title": title.strip(),
        "artworkUrl": _safe_artwork(raw),
    }


def _catalog_album(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    album_id, title = raw.get("browseId"), raw.get("title")
    if not isinstance(album_id, str) or not ALBUM_ID.fullmatch(album_id):
        return None
    if not isinstance(title, str) or not title.strip():
        return None
    return {
        "albumId": album_id,
        "title": title.strip(),
        "artists": _catalog_artist_names(raw.get("artists")),
        "artworkUrl": _safe_artwork(raw),
        "year": str(raw["year"]) if isinstance(raw.get("year"), (int, str)) else None,
    }


@app.get("/suggestions")
def get_suggestions(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=10, ge=1, le=10),
) -> dict[str, Any]:
    def query() -> dict[str, Any]:
        raw = YTMusic().get_search_suggestions(q.strip())
        if not isinstance(raw, list):
            raise HTTPException(status_code=502, detail="YTMUSIC_INVALID_SUGGESTIONS")
        return {
            "source": "youtube_music",
            "suggestions": [
                candidate.strip() for candidate in raw[:limit]
                if isinstance(candidate, str) and candidate.strip()
            ],
        }
    return _catalog_call(query)


@app.get("/albums/{album_id}")
def get_album_catalog(album_id: str) -> dict[str, Any]:
    if not ALBUM_ID.fullmatch(album_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_ALBUM_ID")
    def query() -> dict[str, Any]:
        raw = YTMusic().get_album(album_id)
        if not isinstance(raw, dict) or not isinstance(raw.get("title"), str):
            raise HTTPException(status_code=404, detail="YTMUSIC_ALBUM_NOT_FOUND")
        tracks = raw.get("tracks") or []
        return {
            "source": "youtube_music",
            "album": {
                "albumId": album_id,
                "title": raw["title"].strip(),
                "artists": _catalog_artist_names(raw.get("artists")),
                "artworkUrl": _safe_artwork(raw),
                "year": str(raw["year"]) if isinstance(raw.get("year"), (str, int)) else None,
                "tracks": [
                    item for row in tracks[:100]
                    if (item := _catalog_track(row)) is not None
                ] if isinstance(tracks, list) else [],
            },
            "playbackAvailable": False,
        }
    return _catalog_call(query)


@app.get("/playlists/{playlist_id}")
def get_public_playlist_catalog(
    playlist_id: str,
    limit: int = Query(default=50, ge=1, le=100),
) -> dict[str, Any]:
    if not PLAYLIST_ID.fullmatch(playlist_id):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_PLAYLIST_ID")
    def query() -> dict[str, Any]:
        raw = YTMusic().get_playlist(playlist_id, limit=limit)
        if not isinstance(raw, dict) or not isinstance(raw.get("title"), str):
            raise HTTPException(status_code=404, detail="YTMUSIC_PLAYLIST_NOT_FOUND")
        tracks = raw.get("tracks") or []
        return {
            "source": "youtube_music",
            "playlist": {
                "playlistId": playlist_id,
                "title": raw["title"].strip(),
                "artworkUrl": _safe_artwork(raw),
                "tracks": [
                    item for row in tracks[:limit]
                    if (item := _catalog_track(row)) is not None
                ] if isinstance(tracks, list) else [],
            },
            "playbackAvailable": False,
        }
    return _catalog_call(query)


@app.get("/moods")
def get_mood_catalog() -> dict[str, Any]:
    def query() -> dict[str, Any]:
        raw = YTMusic().get_mood_categories()
        if not isinstance(raw, dict):
            raise HTTPException(status_code=502, detail="YTMUSIC_INVALID_MOODS")
        sections = []
        for section, categories in list(raw.items())[:12]:
            if not isinstance(section, str) or not isinstance(categories, list):
                continue
            items = [
                {"title": row["title"].strip(), "params": row["params"]}
                for row in categories[:30] if isinstance(row, dict)
                and isinstance(row.get("title"), str) and row["title"].strip()
                and isinstance(row.get("params"), str)
                and MOOD_PARAMS.fullmatch(row["params"])
            ]
            if items:
                sections.append({"title": section, "categories": items})
        return {"source": "youtube_music", "sections": sections}
    return _catalog_call(query)


@app.get("/moods/playlists")
def get_mood_playlist_catalog(
    params: str = Query(min_length=6, max_length=256),
    limit: int = Query(default=20, ge=1, le=25),
) -> dict[str, Any]:
    if not MOOD_PARAMS.fullmatch(params):
        raise HTTPException(status_code=400, detail="INVALID_YOUTUBE_MUSIC_MOOD_PARAMS")
    def query() -> dict[str, Any]:
        raw = YTMusic().get_mood_playlists(params)
        if not isinstance(raw, list):
            raise HTTPException(status_code=502, detail="YTMUSIC_INVALID_MOOD_PLAYLISTS")
        return {
            "source": "youtube_music",
            "playlists": [
                item for row in raw[:limit]
                if (item := _catalog_playlist(row)) is not None
            ],
        }
    return _catalog_call(query)


@app.get("/explore")
def get_explore_catalog() -> dict[str, Any]:
    def query() -> dict[str, Any]:
        raw = YTMusic().get_explore()
        if not isinstance(raw, dict):
            raise HTTPException(status_code=502, detail="YTMUSIC_INVALID_EXPLORE")
        releases = raw.get("new_releases") or []
        new_videos = raw.get("new_videos") or []
        trending = raw.get("trending") or {}
        trending_rows = trending.get("items") if isinstance(trending, dict) else []
        top_songs = raw.get("top_songs") or {}
        ranked_rows = top_songs.get("items") if isinstance(top_songs, dict) else []
        return {
            "source": "youtube_music",
            "newReleases": [
                item for row in releases[:30]
                if (item := _catalog_album(row)) is not None
            ] if isinstance(releases, list) else [],
            "newVideos": [
                item for row in new_videos[:30]
                if (item := normalize_video(row)) is not None
            ] if isinstance(new_videos, list) else [],
            "trending": [
                item for row in trending_rows[:30]
                if (item := _catalog_track(row)) is not None
            ] if isinstance(trending_rows, list) else [],
            "topSongsAvailable": bool(isinstance(ranked_rows, list) and ranked_rows),
            "topSongs": [
                item for row in ranked_rows[:30]
                if (item := _catalog_track(row)) is not None
            ] if isinstance(ranked_rows, list) else [],
            "playbackAvailable": False,
        }
    return _catalog_call(query)
