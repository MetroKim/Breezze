import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/api/breezze_api.dart';
import '../../core/auth/auth_session.dart';

/// A music video result from GET /api/v1/video/search.
class BzVideoResult {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationSec;
  final int? viewCount;
  final String embedUrl;

  const BzVideoResult({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationSec,
    this.viewCount,
    required this.embedUrl,
  });

  factory BzVideoResult.fromJson(Map<String, dynamic> json) =>
      BzVideoResult(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Unknown',
        artist: json['artist'] as String? ?? 'Unknown',
        artworkUrl: json['artworkUrl'] as String?,
        durationSec: json['durationSec'] as int?,
        viewCount: json['viewCount'] as int?,
        embedUrl: json['embedUrl'] as String? ?? '',
      );
}

/// A song result from GET /api/v1/search/external.
class BzExternalTrack {
  final String providerTrackId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationSec;

  const BzExternalTrack({
    required this.providerTrackId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationSec,
  });

  factory BzExternalTrack.fromJson(Map<String, dynamic> json) =>
      BzExternalTrack(
        providerTrackId: json['providerTrackId'] as String,
        title: json['title'] as String? ?? 'Unknown',
        artist: json['artist'] as String? ?? 'Unknown',
        artworkUrl: json['artworkUrl'] as String?,
        durationSec: json['durationSec'] as int?,
      );
}

/// Video and external-song search controller. Backend-first per plan
/// section 7: the app talks to the Breezze API, never to the provider.
class VideoSearchController extends Notifier<VideoSearchState> {
  @override
  VideoSearchState build() => const VideoSearchState();

  BreezzeApi get _api => ref.read(authSessionProvider.notifier).api;

  Map<String, String> get _headers => {
        if (_api.accessToken != null)
          'Authorization': 'Bearer ${_api.accessToken}',
      };

  Uri _uri(String path, String query) => Uri.parse(
        '$_api.baseUrl/api/v1$path?q=${Uri.encodeComponent(query)}',
      );

  Future<List<BzVideoResult>> searchVideos(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    state = state.copyWith(videosLoading: true);
    try {
      final res = await http.get(_uri('/video/search', q), headers: _headers);
      if (res.statusCode >= 400) return const [];
      final raw = _extractList(jsonDecode(res.body));
      final videos = [
        for (final item in raw)
          if (item is Map)
            BzVideoResult.fromJson(Map<String, dynamic>.from(item)),
      ];
      state = state.copyWith(videosLoading: false, videos: videos);
      return videos;
    } catch (_) {
      state = state.copyWith(videosLoading: false);
      return const [];
    }
  }

  Future<List<BzExternalTrack>> searchExternalSongs(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    state = state.copyWith(songsLoading: true);
    try {
      final res =
          await http.get(_uri('/search/external', q), headers: _headers);
      if (res.statusCode >= 400) return const [];
      final raw = _extractList(jsonDecode(res.body));
      final tracks = [
        for (final item in raw)
          if (item is Map)
            BzExternalTrack.fromJson(Map<String, dynamic>.from(item)),
      ];
      state = state.copyWith(songsLoading: false, songs: tracks);
      return tracks;
    } catch (_) {
      state = state.copyWith(songsLoading: false);
      return const [];
    }
  }

  /// Handles both envelope shapes: {data: [...]} and the bare array.
  List _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      final data = body['data'];
      if (data is List) return data;
      if (data is Map && data['data'] is List) return data['data'] as List;
    }
    return const [];
  }
}

class VideoSearchState {
  final List<BzVideoResult> videos;
  final List<BzExternalTrack> songs;
  final bool videosLoading;
  final bool songsLoading;

  const VideoSearchState({
    this.videos = const [],
    this.songs = const [],
    this.videosLoading = false,
    this.songsLoading = false,
  });

  VideoSearchState copyWith({
    List<BzVideoResult>? videos,
    List<BzExternalTrack>? songs,
    bool? videosLoading,
    bool? songsLoading,
  }) =>
      VideoSearchState(
        videos: videos ?? this.videos,
        songs: songs ?? this.songs,
        videosLoading: videosLoading ?? this.videosLoading,
        songsLoading: songsLoading ?? this.songsLoading,
      );
}

final videoSearchProvider =
    NotifierProvider<VideoSearchController, VideoSearchState>(
  VideoSearchController.new,
);
