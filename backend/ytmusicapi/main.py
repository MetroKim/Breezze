import re
from threading import BoundedSemaphore
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from ytmusicapi import YTMusic

app = FastAPI(title="Breezze YouTube Music Metadata Adapter", version="1.0.0")
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{6,64}$")
# Each container replica admits at most eight simultaneous upstream requests.
# Extra work is rejected quickly so the FastAPI thread pool cannot be exhausted.
PROVIDER_SLOTS = BoundedSemaphore(8)


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
    if not PROVIDER_SLOTS.acquire(blocking=False):
        raise HTTPException(
            status_code=503,
            detail="YTMUSIC_CAPACITY_EXCEEDED",
            headers={"Retry-After": "2"},
        )
    try:
        results = YTMusic().search(q.strip(), filter="songs", limit=limit)
        tracks = [track for item in results if (track := normalize_track(item))]
        return {"tracks": tracks}
    except Exception as exc:
        # Do not leak provider request headers, cookies, or upstream payloads.
        raise HTTPException(status_code=502, detail="YTMUSIC_UPSTREAM_UNAVAILABLE") from exc
    finally:
        PROVIDER_SLOTS.release()



def normalize_video(item: dict[str, Any]) -> dict[str, Any] | None:
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
