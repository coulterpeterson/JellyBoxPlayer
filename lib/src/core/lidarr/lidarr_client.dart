import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';

class LidarrException implements Exception {
  const LidarrException(
    this.message, {
    this.isUnauthorized = false,
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  bool get isNotFound => statusCode == 404;
  final bool isUnauthorized;

  @override
  String toString() => message;
}

/// A minimal client for the Lidarr v1 API, authenticated with an API key.
class LidarrClient {
  LidarrClient({required this.baseUrl, required this.apiKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  /// Turns user input such as `nas:8686` into `http://nas:8686`.
  static String? normalizeUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  Uri _uri(String path, [Map<String, Object?> query = const {}]) {
    final base = Uri.parse(baseUrl);
    final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(
      path: '$prefix/api/v1/$path',
      queryParameters: {
        for (final MapEntry(:key, :value) in query.entries)
          if (value != null)
            key: value is List ? value.map((e) => '$e').toList() : '$value',
      },
    );
  }

  Options get _options => Options(
    headers: {'X-Api-Key': apiKey},
    responseType: ResponseType.json,
  );

  Future<T> _send<T>(
    String label,
    Future<Response<T>> Function() request,
  ) async {
    try {
      final response = await request();
      debugPrint('[Lidarr] $label -> ${response.statusCode}');
      return response.data as T;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      debugPrint(
        '[Lidarr] $label -> ${status ?? error.type.name} '
        '${_summarize(error.response?.data)}',
      );
      if (status == 401 || status == 403) {
        throw const LidarrException(
          'Lidarr rejected the API key',
          isUnauthorized: true,
        );
      }
      final data = error.response?.data;
      final detail = switch (data) {
        {'message': final String message} => message,
        [{'errorMessage': final String message}, ...] => message,
        _ => error.message ?? 'HTTP $status',
      };
      throw LidarrException(detail, statusCode: status);
    }
  }

  Future<Object?> _get(String path, [Map<String, Object?> query = const {}]) =>
      _send(
        'GET $path ${query.isEmpty ? '' : query}',
        () => _dio.getUri<Object?>(_uri(path, query), options: _options),
      );

  Future<Object?> _post(String path, Object? body) => _send(
    'POST $path',
    () => _dio.postUri<Object?>(_uri(path), data: body, options: _options),
  );

  Future<Object?> _put(String path, Object? body) => _send(
    'PUT $path',
    () => _dio.putUri<Object?>(_uri(path), data: body, options: _options),
  );

  Future<Object?> _delete(String path, [Object? body]) => _send(
    'DELETE $path',
    () => _dio.deleteUri<Object?>(_uri(path), data: body, options: _options),
  );

  static String _summarize(Object? data) {
    final text = '$data';
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }

  static List<Map<String, dynamic>> _list(Object? data) => [
    for (final entry in data as List? ?? const [])
      if (entry is Map) entry.cast<String, dynamic>(),
  ];

  /// Returns Lidarr's version, verifying the address and API key.
  Future<String> systemVersion() async {
    final data = await _get('system/status');
    if (data is! Map || data['version'] == null) {
      throw const LidarrException('That address is not a Lidarr server');
    }
    return data['version'] as String;
  }

  Future<List<LidarrAlbum>> searchAlbums(String term) async {
    final data = await _get('album/lookup', {'term': term});
    return [for (final json in _list(data)) LidarrAlbum(json)];
  }

  /// Lidarr's own search (what its Add New page uses): artists and albums.
  Future<({List<LidarrArtist> artists, List<LidarrAlbum> albums})> search(
    String term,
  ) async {
    final results = _list(await _get('search', {'term': term}));
    final artists = <LidarrArtist>[];
    final albums = <LidarrAlbum>[];
    for (final result in results) {
      if (result['artist'] case final Map<dynamic, dynamic> artist) {
        artists.add(LidarrArtist(artist.cast<String, dynamic>()));
      } else if (result['album'] case final Map<dynamic, dynamic> album) {
        albums.add(LidarrAlbum(album.cast<String, dynamic>()));
      }
    }
    return (artists: artists, albums: albums);
  }

  /// Finds an album by its MusicBrainz release group id. Returns Lidarr's
  /// stored album when it already tracks it.
  Future<LidarrAlbum?> lookupAlbum(String releaseGroupId) async {
    final albums = await searchAlbums('lidarr:$releaseGroupId');
    return albums.firstOrNull;
  }

  Future<List<LidarrAlbum>> artistAlbums(int artistId) async {
    final data = await _get('album', {'artistId': artistId});
    return [for (final json in _list(data)) LidarrAlbum(json)];
  }

  /// Makes [releaseId] the album's monitored release, so Lidarr grabs that
  /// edition. Returns false when the album has no such release.
  Future<bool> monitorRelease(int albumId, int releaseId) async {
    final data = await _get('album/$albumId');
    final json = (data! as Map).cast<String, dynamic>();
    final releases = [
      for (final release in json['releases'] as List? ?? const [])
        if (release is Map) release.cast<String, dynamic>(),
    ];
    if (!releases.any((r) => r['id'] == releaseId)) return false;
    await _put('album/$albumId', {
      ...json,
      'releases': [
        for (final release in releases)
          {...release, 'monitored': release['id'] == releaseId},
      ],
    });
    return true;
  }

  Future<LidarrAlbum> album(int id) async {
    final data = await _get('album/$id');
    return LidarrAlbum((data! as Map).cast<String, dynamic>());
  }

  Future<LidarrAlbum?> albumByForeignId(String foreignAlbumId) async {
    final data = await _get('album', {'foreignAlbumId': foreignAlbumId});
    final albums = _list(data);
    return albums.isEmpty ? null : LidarrAlbum(albums.first);
  }

  Future<List<LidarrTrack>> tracks(int albumId) async {
    final data = await _get('track', {'albumId': albumId});
    return [for (final json in _list(data)) LidarrTrack.fromJson(json)]
      ..sort((a, b) {
        final disc = a.discNumber.compareTo(b.discNumber);
        return disc != 0 ? disc : a.number.compareTo(b.number);
      });
  }

  Future<List<LidarrTrack>> releaseTracks(int releaseId) async {
    final data = await _get('track', {'albumReleaseId': releaseId});
    return [for (final json in _list(data)) LidarrTrack.fromJson(json)];
  }

  /// Asks Lidarr's indexers what they have for an album, like Lidarr's
  /// interactive search, including why each result would be rejected.
  /// This can take a while; indexers are queried live.
  Future<List<({String title, bool rejected, List<String> rejections})>>
  releaseCandidates(int albumId) async {
    final data = await _send(
      'GET release albumId=$albumId',
      () => _dio.getUri<Object?>(
        _uri('release', {'albumId': albumId}),
        options: _options.copyWith(receiveTimeout: const Duration(minutes: 2)),
      ),
    );
    return [
      for (final json in _list(data))
        (
          title: json['title'] as String? ?? '',
          rejected: json['rejected'] as bool? ?? false,
          rejections: [
            for (final reason in json['rejections'] as List? ?? const [])
              '$reason',
          ],
        ),
    ];
  }

  Future<List<LidarrQueueItem>> queue() async {
    final data = await _get('queue', {
      'pageSize': 200,
      'includeAlbum': false,
      'includeArtist': false,
    });
    final records = data is Map ? data['records'] : data;
    return [for (final json in _list(records)) LidarrQueueItem(json)];
  }

  /// Monitors [album] and starts a search for it, adding its artist to
  /// Lidarr first if needed. Returns the stored album.
  ///
  /// A new artist is added with only this album monitored
  /// (`albumsToMonitor`), so Lidarr's post-add scan doesn't unmonitor it
  /// and nothing else from the artist gets downloaded.
  Future<LidarrAlbum> addAlbum(LidarrAlbum album) async {
    debugPrint(
      '[Lidarr] request "${album.title}" by ${album.artistName} '
      '(album ${album.id}, ${album.foreignAlbumId})',
    );
    if (album.isInLidarr) {
      await setMonitored([album.id], monitored: true);
      await searchAlbum(album.id);
      return this.album(album.id);
    }

    final artistId = (album.artist['id'] as num?)?.toInt() ?? 0;
    final Map<String, dynamic> artist;
    if (artistId > 0) {
      artist = album.artist;
    } else {
      final rootFolders = _list(await _get('rootfolder'));
      if (rootFolders.isEmpty) {
        throw const LidarrException('Lidarr has no root folder set up');
      }
      final root = rootFolders.first;
      artist = {
        ...album.artist,
        'qualityProfileId':
            root['defaultQualityProfileId'] ??
            _list(await _get('qualityprofile')).firstOrNull?['id'],
        'metadataProfileId':
            root['defaultMetadataProfileId'] ??
            _list(await _get('metadataprofile')).firstOrNull?['id'],
        'rootFolderPath': root['path'],
        'monitored': true,
        'monitorNewItems': 'none',
        'addOptions': {
          'monitor': 'none',
          'albumsToMonitor': [album.foreignAlbumId],
          'searchForMissingAlbums': true,
        },
      };
    }
    final data = await _post('album', {
      ...album.json,
      'monitored': true,
      'addOptions': {'searchForNewAlbum': true},
      'artist': artist,
    });
    return LidarrAlbum((data! as Map).cast<String, dynamic>());
  }

  Future<void> searchAlbum(int albumId) => _post('command', {
    'name': 'AlbumSearch',
    'albumIds': [albumId],
  });

  Future<void> setMonitored(List<int> albumIds, {required bool monitored}) =>
      _put('album/monitor', {'albumIds': albumIds, 'monitored': monitored});

  Future<void> deleteTrackFiles(List<int> trackFileIds) async {
    if (trackFileIds.isEmpty) return;
    await _delete('trackfile/bulk', {'trackFileIds': trackFileIds});
  }
}
