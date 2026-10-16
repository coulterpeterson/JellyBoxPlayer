import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';

/// Song search through Deezer's public API, which needs no account and
/// ranks by popularity. Results carry an ISRC that MusicBrainz maps to
/// the albums containing the song.
class DeezerClient {
  DeezerClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.deezer.com',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;

  Future<List<CatalogSong>> searchTracks(String term, {int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/search/track',
      queryParameters: {'q': term, 'limit': limit},
    );
    final data = response.data ?? const {};
    if (data['error'] case final Map<dynamic, dynamic> error) {
      debugPrint('[Deezer] search failed: ${error['message']}');
      return const [];
    }
    final songs = <CatalogSong>[];
    final seen = <String>{};
    for (final json in data['data'] as List? ?? const []) {
      if (json is! Map) continue;
      final artist = (json['artist'] as Map?)?['name'] as String? ?? '';
      final album = json['album'] as Map?;
      final title = json['title'] as String? ?? '';
      // Deezer lists the same song once per release; keep the top one.
      if (!seen.add('${normalizeTitle(title)}|${normalizeTitle(artist)}')) {
        continue;
      }
      songs.add(
        CatalogSong(
          title: title,
          artistName: artist,
          albumTitle: album?['title'] as String?,
          coverUrl: (album?['cover_medium'] ?? album?['cover']) as String?,
          duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
          isrc: json['isrc'] as String?,
          deezerId: (json['id'] as num?)?.toInt(),
        ),
      );
    }
    return songs;
  }

  /// The ISRC of a track, for search results that don't include one.
  Future<String?> isrcOf(int trackId) async {
    final response = await _dio.get<Map<String, dynamic>>('/track/$trackId');
    return response.data?['isrc'] as String?;
  }
}
