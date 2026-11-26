"""Sanitized nonproduction test of existing Breezze ytmusicapi candidate logic.

Default video: Blender Foundation Big Buck Bunny (CC BY 3.0).
No downloads, cookies, decrypted signatures, or persistent media URLs.
"""
import json
import os

from ytmusicapi import YTMusic
from main import select_audio_candidate

video_id = os.environ.get("BREEZZE_PROBE_VIDEO_ID", "aqz-KE-bpKQ")
report = {
    "source": "ytmusicapi",
    "videoId": video_id,
    "sample": "Big Buck Bunny / Blender Foundation / CC BY 3.0",
    "hasPlayerResponse": False,
    "playabilityStatus": None,
    "directAudioCandidate": False,
    "failure": None,
}
try:
    response = YTMusic().get_song(video_id)
    report["hasPlayerResponse"] = isinstance(response, dict)
    playability = response.get("playabilityStatus") or {}
    if isinstance(playability, dict):
        status = playability.get("status")
        report["playabilityStatus"] = status if status in (
            "OK", "LOGIN_REQUIRED", "UNPLAYABLE", "ERROR", "CONTENT_CHECK_REQUIRED"
        ) else "UNKNOWN"
    report["directAudioCandidate"] = select_audio_candidate(response) is not None
except Exception as error:
    # Do not print exception text: upstream exceptions can embed URL/query secrets.
    report["failure"] = type(error).__name__

print("BREEZZE_YTMUSIC_CANDIDATE_PROBE=" + json.dumps(report, separators=(",", ":")))
if not report["directAudioCandidate"]:
    raise SystemExit(1)
