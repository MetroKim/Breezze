"""Contract tests for the private, unauthenticated ytmusicapi catalog sidecar.

These tests stub all upstream calls. They prove response normalization and
bounds, not the availability of YouTube Music or a native playback licence.
"""
import json
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


if __name__ == "__main__":
    unittest.main()
