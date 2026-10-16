import 'package:dio/dio.dart';
import 'package:jplayer/src/domain/models/models.dart';

/// Looks up lyrics on LRCLIB (https://lrclib.net), a free, open lyrics
/// database that needs no account or API key.
class LrclibClient {
  LrclibClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://lrclib.net/api',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {
                'User-Agent':
                    'JellyBoxPlayer (https://github.com/avdept/JellyBoxPlayer)',
              },
            ),
          );

  final Dio _dio;

  Future<Lyrics?> lyricsFor(LibraryItem song) async {
    final artist = song.artistLabel.trim();
    final title = song.name.trim();
    if (title.isEmpty) return null;

    final exact = await _get(song, artist: artist, title: title);
    if (exact != null) return exact;
    return _search(song, artist: artist, title: title);
  }

  Future<Lyrics?> _get(
    LibraryItem song, {
    required String artist,
    required String title,
  }) async {
    if (artist.isEmpty) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/get',
        queryParameters: {
          'artist_name': artist,
          'track_name': title,
          if (song.albumName case final album? when album.isNotEmpty)
            'album_name': album,
          if (song.duration > Duration.zero)
            'duration': song.duration.inSeconds,
        },
      );
      return _toLyrics(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Lyrics?> _search(
    LibraryItem song, {
    required String artist,
    required String title,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/search',
      queryParameters: {
        'track_name': title,
        if (artist.isNotEmpty) 'artist_name': artist,
      },
    );
    final results = (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (results.isEmpty) return null;

    // Prefer the closest duration match, and synced lyrics over plain ones.
    final seconds = song.duration.inSeconds;
    int score(Map<String, dynamic> entry) {
      final duration = (entry['duration'] as num?)?.round() ?? 0;
      final drift = seconds > 0 ? (duration - seconds).abs() : 0;
      final synced = (entry['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      return drift + (synced ? 0 : 5);
    }

    results.sort((a, b) => score(a).compareTo(score(b)));
    final best = results.first;
    if (seconds > 0) {
      final duration = (best['duration'] as num?)?.round() ?? 0;
      if (duration > 0 && (duration - seconds).abs() > 10) return null;
    }
    return _toLyrics(best);
  }

  Lyrics? _toLyrics(Map<String, dynamic>? data) {
    if (data == null || data['instrumental'] == true) return null;
    final synced = data['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      final parsed = parseLrc(synced);
      if (parsed.lines.isNotEmpty) return parsed;
    }
    final plain = data['plainLyrics'] as String?;
    if (plain == null || plain.trim().isEmpty) return null;
    return Lyrics(
      lines: [
        for (final line in plain.split('\n')) LyricLine(text: line.trim()),
      ],
    );
  }
}

final _lrcTimestamp = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC formatted lyrics (`[mm:ss.xx] line`) into synced [Lyrics].
Lyrics parseLrc(String source) {
  final lines = <LyricLine>[];
  for (final raw in source.split('\n')) {
    final stamps = _lrcTimestamp.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final text = raw.substring(stamps.last.end).trim();
    for (final stamp in stamps) {
      final minutes = int.parse(stamp.group(1)!);
      final seconds = int.parse(stamp.group(2)!);
      final fraction = stamp.group(3) ?? '0';
      final millis = int.parse(fraction.padRight(3, '0').substring(0, 3));
      lines.add(
        LyricLine(
          text: text,
          start: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: millis,
          ),
        ),
      );
    }
  }
  lines.sort((a, b) => a.start!.compareTo(b.start!));
  return Lyrics(lines: lines, isSynced: lines.isNotEmpty);
}
