"""Contract tests for the private, unauthenticated ytmusicapi catalog sidecar.

These tests stub all upstream calls. They prove response normalization and
bounds, not the availability of YouTube Music or a native playback licence.
"""
import json
from datetime import datetime, timezone
import unittest
from unittest.mock import patch

from fastapi import HTTPException

import main


SONG_ID = "abcdefghijk"
ALBUM_ID = "MPREabcdefghij"
PLAYLIST_ID = "OLAK5uy_abcdefghijkl"


class FakeMusic:
    def get_search_suggestions(self, query):
        return [query, query + " songs"]

    def get_album(self, album_id):
        return {
            "title": "Example album",
            "year": "2024",
            "artists": [{"name": "Artist"}],
            "thumbnails": [{"url": "https://example.com/cover.jpg"}],
            "tracks": [{
                "videoId": SONG_ID,
                "title": "Song",
                "duration_seconds": 193,
                "artists": [{"name": "Artist"}],
                "streamingData": {"adaptiveFormats": [{
                    "url": "https://forbidden.example/signed-media",
                }]},
                "cookie": "should never be exposed",
            }],
        }

    def get_playlist(self, playlist_id, limit=50):
        return {
            "title": "Public playlist",
            "tracks": [{
                "videoId": SONG_ID,
                "title": "Song",
                "artists": [{"name": "Artist"}],
                "duration": "3:13",
                "streamingData": {"url": "https://forbidden.example/audio"},
            }],
        }

    def get_mood_categories(self):
        return {"Genres": [
            {"title": "Afrobeats", "params": "ggMPOg1uX1ZwN0pHT2NBT1Fk"},
            {"title": "invalid", "params": "../private"},
        ]}

    def get_mood_playlists(self, params):
        return [{"title": "Afrobeats mix", "playlistId": PLAYLIST_ID}]

    def get_explore(self):
        return {
            "new_releases": [{
                "browseId": ALBUM_ID,
                "title": "Example album",
                "artists": [{"name": "Artist"}],
            }],
            "new_videos": [{
                "videoId": SONG_ID,
                "title": "Video",
                "videoType": "MUSIC_VIDEO_TYPE_OMV",
                "streamingData": "secret",
            }],
            "trending": {"items": [{
                "videoId": SONG_ID, "title": "Trending song",
                "artists": [{"name": "Artist"}],
            }]},
            "top_songs": {},
        }


class PublicCatalogContractTest(unittest.TestCase):
    def setUp(self):
        self.client_patch = patch.object(main, "YTMusic", FakeMusic)
        self.client_patch.start()
        self.addCleanup(self.client_patch.stop)

    def test_album_strips_media_urls_and_cookies(self):
        response = main.get_album_catalog(ALBUM_ID)
        self.assertEqual(response["album"]["tracks"][0]["durationSec"], 193)
        self.assertFalse(response["playbackAvailable"])
        serialized = json.dumps(response)
        self.assertNotIn("streamingData", serialized)
        self.assertNotIn("forbidden.example", serialized)
        self.assertNotIn("cookie", serialized)

    def test_public_playlist_returns_only_bounded_song_metadata(self):
        response = main.get_public_playlist_catalog(PLAYLIST_ID, limit=5)
        self.assertEqual(response["playlist"]["tracks"][0]["title"], "Song")
        self.assertFalse(response["playbackAvailable"])
        self.assertNotIn("streamingData", json.dumps(response))

    def test_suggestions_and_mood_categories_are_sanitized(self):
        self.assertEqual(main.get_suggestions("Afrobeats", limit=2)["suggestions"],
                         ["Afrobeats", "Afrobeats songs"])
        moods = main.get_mood_catalog()
        self.assertEqual(len(moods["sections"][0]["categories"]), 1)
        self.assertEqual(main.get_mood_playlist_catalog(
            "ggMPOg1uX1ZwN0pHT2NBT1Fk", limit=5,
        )["playlists"][0]["title"], "Afrobeats mix")

    def test_explore_provides_only_verified_category_items(self):
        result = main.get_explore_catalog()
        self.assertFalse(result["topSongsAvailable"])
        self.assertEqual(result["newReleases"][0]["title"], "Example album")
        self.assertEqual(result["newVideos"][0]["classification"],
                         "youtube_music_original_music_video")
        self.assertNotIn("streamingData", json.dumps(result))

    def test_invalid_ids_are_rejected_without_upstream_requests(self):
        for func, arg in [
            (main.get_album_catalog, "../private"),
            (main.get_public_playlist_catalog, "../private"),
            (main.get_mood_playlist_catalog, "../private"),
        ]:
            with self.subTest(func=func.__name__):
                with self.assertRaises(HTTPException) as caught:
                    func(arg)
                self.assertEqual(caught.exception.status_code, 400)

    def test_provider_errors_redact_upstream_details(self):
        with patch.object(FakeMusic, "get_album",
                          side_effect=RuntimeError("secret cookie should not escape")):
            with self.assertRaises(HTTPException) as caught:
                main.get_album_catalog(ALBUM_ID)
            self.assertEqual(caught.exception.status_code, 502)
            self.assertEqual(caught.exception.detail,
                             "YTMUSIC_CATALOG_UPSTREAM_UNAVAILABLE")


class ExperimentalAudioCandidateTest(unittest.TestCase):
    """Only direct, unexpired YouTube audio URLs may reach the dev experiment."""

    def _response(self, urls):
        return {
            "playabilityStatus": {"status": "OK"},
            "streamingData": {
                "adaptiveFormats": [
                    {"url": url, "mimeType": "audio/mp4; codecs=mp4a.40.2",
                     "bitrate": 128000 + index * 1000}
                    for index, url in enumerate(urls)
                ],
            },
        }

    def test_selects_the_direct_unexpired_audio_url(self):
        expiry = int(datetime.now(timezone.utc).timestamp()) + 600
        urls = [
            f"https://rr4---sn-x.googlevideo.com/videoplayback?expire={expiry}",
            f"https://malicious.example.com/stream?expire={expiry}",
        ]
        candidate = main.select_audio_candidate(self._response(urls))
        self.assertIsNotNone(candidate)
        self.assertEqual(candidate["streamUrl"], urls[0])
        self.assertEqual(candidate["mimeType"], "audio/mp4")

    def test_rejects_expired_untrusted_video_and_cipher_only_formats(self):
        now = int(datetime.now(timezone.utc).timestamp())
        song = self._response([
            f"https://evilgooglevideo.com/stream?expire={now+600}",
            f"http://rr4.googlevideo.com/videoplayback?expire={now+600}",
            f"https://rr4.googlevideo.com/videoplayback?expire={now-30}",
        ])
        song["streamingData"]["adaptiveFormats"].extend([
            {"mimeType": "audio/mp4", "bitrate": 128000,
             "signatureCipher": "secret"},
            {"mimeType": "video/mp4", "bitrate": 240000,
             "url": f"https://rr4.googlevideo.com/videoplayback?expire={now+600}"},
        ])
        self.assertIsNone(main.select_audio_candidate(song))
        song["playabilityStatus"] = {"status": "LOGIN_REQUIRED"}
        self.assertIsNone(main.select_audio_candidate(song))

    def test_endpoint_disabled_by_default_and_in_production(self):
        with patch.dict(main.os.environ, {
            "BREEZZE_YTMUSIC_AUDIO_EXPERIMENT": "false",
            "RAILWAY_ENVIRONMENT_NAME": "staging",
        }):
            with self.assertRaises(HTTPException) as caught:
                main.get_audio_candidate(SONG_ID)
            self.assertEqual(caught.exception.detail, "EXPERIMENT_DISABLED")

        with patch.dict(main.os.environ, {
            "BREEZZE_YTMUSIC_AUDIO_EXPERIMENT": "true",
            "RAILWAY_ENVIRONMENT_NAME": "production",
        }):
            with self.assertRaises(HTTPException) as caught:
                main.get_audio_candidate(SONG_ID)
            self.assertEqual(caught.exception.status_code, 404)

    def test_dev_probe_returns_candidate_but_no_raw_song_metadata(self):
        expiry = int(datetime.now(timezone.utc).timestamp()) + 600
        song = self._response([
            f"https://rr4.googlevideo.com/videoplayback?expire={expiry}",
        ])
        song["cookie"] = "SENSITIVE_DO_NOT_EXPOSE"
        with patch.dict(main.os.environ, {
            "BREEZZE_YTMUSIC_AUDIO_EXPERIMENT": "true",
            "RAILWAY_ENVIRONMENT_NAME": "staging",
        }):
            with patch.object(main, "YTMusic") as yt_music:
                yt_music.return_value.get_song.return_value = song
                result = main.get_audio_candidate(SONG_ID)
        self.assertTrue(result["experimental"])
        self.assertIn("googlevideo.com", result["candidate"]["streamUrl"])
        self.assertNotIn("SENSITIVE_DO_NOT_EXPOSE", json.dumps(result))
        yt_music.return_value.get_song.assert_called_once_with(SONG_ID)


if __name__ == "__main__":
    unittest.main()
