import 'package:dio/dio.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';

class LidarrException implements Exception {
  const LidarrException(this.message, {this.isUnauthorized = false});

  final String message;
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

  Future<T> _send<T>(Future<Response<T>> Function() request) async {
    try {
      final response = await request();
      return response.data as T;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
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
      throw LidarrException(detail);
    }
  }

  Future<Object?> _get(String path, [Map<String, Object?> query = const {}]) =>
      _send(() => _dio.getUri<Object?>(_uri(path, query), options: _options));

  Future<Object?> _post(String path, Object? body) => _send(
    () => _dio.postUri<Object?>(_uri(path), data: body, options: _options),
  );

  Future<Object?> _put(String path, Object? body) => _send(
    () => _dio.putUri<Object?>(_uri(path), data: body, options: _options),
  );

  Future<Object?> _delete(String path, [Object? body]) => _send(
    () => _dio.deleteUri<Object?>(_uri(path), data: body, options: _options),
  );

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

  Future<List<LidarrQueueItem>> queue() async {
    final data = await _get('queue', {
      'pageSize': 200,
      'includeAlbum': false,
      'includeArtist': false,
    });
    final records = data is Map ? data['records'] : data;
    return [for (final json in _list(records)) LidarrQueueItem(json)];
  }

  /// Adds [album] (and its artist, if Lidarr doesn't know it yet) as a
  /// monitored album and starts a search for it. Returns the stored album.
  Future<LidarrAlbum> addAlbum(LidarrAlbum album) async {
    if (album.isInLidarr) {
      await setMonitored([album.id], monitored: true);
      await searchAlbum(album.id);
      return this.album(album.id);
    }

    final rootFolders = _list(await _get('rootfolder'));
    if (rootFolders.isEmpty) {
      throw const LidarrException('Lidarr has no root folder set up');
    }
    final root = rootFolders.first;
    final qualityProfileId =
        root['defaultQualityProfileId'] ??
        _list(await _get('qualityprofile')).firstOrNull?['id'];
    final metadataProfileId =
        root['defaultMetadataProfileId'] ??
        _list(await _get('metadataprofile')).firstOrNull?['id'];

    final artistId = album.artist['id'];
    final existingArtist = artistId is num && artistId > 0;
    final body = {
      ...album.json,
      'monitored': true,
      'addOptions': {'searchForNewAlbum': true},
      'artist': {
        ...album.artist,
        if (!existingArtist) ...{
          'qualityProfileId': qualityProfileId,
          'metadataProfileId': metadataProfileId,
          'rootFolderPath': root['path'],
          'monitored': true,
          'monitorNewItems': 'none',
          'addOptions': {
            'monitor': 'none',
            'searchForMissingAlbums': false,
          },
        },
      },
    };
    final data = await _post('album', body);
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
