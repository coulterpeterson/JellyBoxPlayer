import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';

/// Searches MusicBrainz, the open music database Lidarr is built on, so
/// results map straight onto Lidarr's ids (release group = album).
/// MusicBrainz allows about one request a second, so calls are queued.
class MusicBrainzClient {
  MusicBrainzClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://musicbrainz.org/ws/2',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {
                'User-Agent':
                    'JellyBoxPlayer/2 (https://github.com/avdept/JellyBoxPlayer)',
                'Accept': 'application/json',
              },
            ),
          );

  final Dio _dio;
  Future<void> _queue = Future<void>.value();
  DateTime _last = DateTime(2000);
  static const _gap = Duration(milliseconds: 1100);

  /// Runs requests one at a time, at most one a second, retrying when
  /// MusicBrainz says it's busy.
  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, Object?> query,
  ) {
    final completer = Completer<Map<String, dynamic>>();
    _queue = _queue.then((_) async {
      for (var attempt = 0; ; attempt++) {
        final wait = _gap - DateTime.now().difference(_last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        _last = DateTime.now();
        try {
          final response = await _dio.get<Map<String, dynamic>>(
            path,
            queryParameters: {...query, 'fmt': 'json'},
          );
          completer.complete(response.data ?? const {});
          return;
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if ((status == 503 || status == 429) && attempt < 3) {
            await Future<void>.delayed(Duration(seconds: 1 + attempt * 2));
            continue;
          }
          debugPrint('[MusicBrainz] $path failed: ${status ?? error.type}');
          completer.completeError(error);
          return;
        }
      }
    });
    return completer.future;
  }

  /// Escapes Lucene query syntax in user input.
  static String escape(String term) => term.replaceAllMapped(
    RegExp(r'[+\-&|!(){}\[\]^"~*?:\\/]'),
    (m) => '\\${m[0]}',
  );

  static String coverUrl(String releaseGroupId) =>
      'https://coverartarchive.org/release-group/$releaseGroupId/front-250';

  static CatalogAlbum _releaseGroup(Map<String, dynamic> json) {
    final credits = json['artist-credit'] as List? ?? const [];
    final artist = [
      for (final credit in credits)
        if (credit is Map)
          '${credit['name'] ?? ''}${credit['joinphrase'] ?? ''}',
    ].join();
    final date = json['first-release-date'] as String? ?? '';
    return CatalogAlbum(
      releaseGroupId: json['id'] as String,
      title: json['title'] as String? ?? '',
      artistName: artist,
      primaryType: json['primary-type'] as String?,
      secondaryTypes: [
        for (final type in json['secondary-types'] as List? ?? const [])
          '$type',
      ],
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      coverUrl: coverUrl(json['id'] as String),
    );
  }

  /// Albums matching [term] by name, including soundtracks and other
  /// releases Lidarr's own search tends to miss. MusicBrainz has no
  /// popularity ranking, so a soundtrack-focused query is merged in and
  /// ties go to the newest release.
  Future<List<CatalogAlbum>> searchReleaseGroups(String term) async {
    final escaped = escape(term);
    final scored = <String, (int, CatalogAlbum)>{};
    for (final query in [
      '$escaped AND status:official',
      '$escaped AND status:official AND secondarytype:soundtrack',
    ]) {
      final data = await _get('/release-group', {'query': query, 'limit': 25});
      for (final json in data['release-groups'] as List? ?? const []) {
        if (json is! Map) continue;
        final score = (json['score'] as num?)?.toInt() ?? 0;
        if (score < 70) continue;
        final album = _releaseGroup(json.cast<String, dynamic>());
        final existing = scored[album.releaseGroupId];
        if (existing == null || existing.$1 < score) {
          scored[album.releaseGroupId] = (score, album);
        }
      }
    }
    final ranked = scored.values.toList()
      ..sort((a, b) {
        final byScore = b.$1.compareTo(a.$1);
        if (byScore != 0) return byScore;
        return (b.$2.year ?? 0).compareTo(a.$2.year ?? 0);
      });
    return [for (final (_, album) in ranked) album];
  }

  /// An artist's albums, EPs and singles, for artists Lidarr doesn't track.
  Future<List<CatalogAlbum>> artistReleaseGroups(String artistId) async {
    final albums = <CatalogAlbum>[];
    for (var offset = 0; offset < 400; offset += 100) {
      final data = await _get('/release-group', {
        'artist': artistId,
        'limit': 100,
        'offset': offset,
      });
      final page = data['release-groups'] as List? ?? const [];
      albums.addAll([
        for (final json in page)
          if (json is Map) _releaseGroup(json.cast<String, dynamic>()),
      ]);
      final total = (data['release-group-count'] as num?)?.toInt() ?? 0;
      if (page.length < 100 || albums.length >= total) break;
    }
    return albums;
  }

  /// Albums containing the recordings with this ISRC.
  Future<SongSource> songByIsrc(String isrc) async {
    final data = await _get('/isrc/$isrc', const {});
    final recordings = <Map<dynamic, dynamic>>[];
    // The ISRC endpoint can't include release groups, so look the
    // recordings up again (an ISRC rarely maps to more than two).
    for (final json in (data['recordings'] as List? ?? const []).take(2)) {
      if (json is! Map || json['id'] == null) continue;
      recordings.add(
        await _get('/recording/${json['id']}', {
          'inc': 'releases release-groups artist-credits',
        }),
      );
    }
    return _songSource(recordings);
  }

  /// Albums containing a song, found by title and artist.
  Future<SongSource> songByName(String title, String artist) async {
    final data = await _get('/recording', {
      'query':
          'recording:"${escape(title)}" AND artist:"${escape(artist)}" '
          'AND status:official AND NOT secondarytype:(live OR compilation)',
      'limit': 25,
    });
    final recordings = [
      for (final json in data['recordings'] as List? ?? const [])
        if (json is Map &&
            normalizeTitle('${json['title']}') == normalizeTitle(title))
          json,
    ];
    return _songSource(recordings);
  }

  SongSource _songSource(List<dynamic> recordings) {
    final ids = <String>{};
    final albums = <String, CatalogAlbum>{};
    for (final recording in recordings.whereType<Map<dynamic, dynamic>>()) {
      ids.add(recording['id'] as String);
      final credits = recording['artist-credit'] as List? ?? const [];
      final artist = [
        for (final credit in credits)
          if (credit is Map)
            '${credit['name'] ?? ''}${credit['joinphrase'] ?? ''}',
      ].join();
      for (final release in recording['releases'] as List? ?? const []) {
        if (release is! Map) continue;
        if (release['status'] != null && release['status'] != 'Official') {
          continue;
        }
        final group = release['release-group'];
        if (group is! Map || group['id'] == null) continue;
        final album = _releaseGroup({
          ...group.cast<String, dynamic>(),
          'first-release-date':
              group['first-release-date'] ?? release['date'] ?? '',
          if (group['artist-credit'] == null) 'artist-credit': credits,
        });
        final existing = albums[album.releaseGroupId];
        if (existing == null ||
            (album.year ?? 9999) < (existing.year ?? 9999)) {
          albums[album.releaseGroupId] = album.artistName.isEmpty
              ? CatalogAlbum(
                  releaseGroupId: album.releaseGroupId,
                  title: album.title,
                  artistName: artist,
                  primaryType: album.primaryType,
                  secondaryTypes: album.secondaryTypes,
                  year: album.year,
                  coverUrl: album.coverUrl,
                )
              : album;
        }
      }
    }
    return SongSource(albums: albums.values.toList(), recordingIds: ids);
  }

  Future<List<LidarrTrack>> releaseGroupTracks(String releaseGroupId) async {
    final data = await _get(
      '/release',
      {
        'release-group': releaseGroupId,
        'inc': 'recordings',
        'status': 'official',
        'limit': 25,
      },
    );
    final releases = [
      for (final release in data['releases'] as List? ?? const [])
        if (release is Map) release.cast<String, dynamic>(),
    ];
    if (releases.isEmpty) return const [];

    // Lidarr usually picks the release with the most common track count;
    // the first official digital or CD release is a good approximation.
    int trackTotal(Map<String, dynamic> release) => [
      for (final medium in release['media'] as List? ?? const [])
        (medium as Map)['track-count'] as int? ?? 0,
    ].fold(0, (a, b) => a + b);
    releases.sort((a, b) {
      final countryA = a['country'] == 'XW' || a['country'] == 'US' ? 0 : 1;
      final countryB = b['country'] == 'XW' || b['country'] == 'US' ? 0 : 1;
      if (countryA != countryB) return countryA.compareTo(countryB);
      return trackTotal(a).compareTo(trackTotal(b));
    });
    final release = releases.first;

    return [
      for (final (discIndex, medium) in (release['media'] as List).indexed)
        for (final track in (medium as Map)['tracks'] as List? ?? const [])
          if (track is Map)
            LidarrTrack(
              title: track['title'] as String? ?? '',
              number: track['position'] as int? ?? 0,
              discNumber: medium['position'] as int? ?? discIndex + 1,
              recordingId: (track['recording'] as Map?)?['id'] as String?,
              duration: Duration(milliseconds: track['length'] as int? ?? 0),
            ),
    ];
  }
}
