import 'package:dio/dio.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';

/// Reads track listings from MusicBrainz for albums Lidarr hasn't added
/// yet. Lidarr identifies albums by their MusicBrainz release group id.
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

  Future<List<LidarrTrack>> releaseGroupTracks(String releaseGroupId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/release',
      queryParameters: {
        'release-group': releaseGroupId,
        'inc': 'recordings',
        'status': 'official',
        'limit': 25,
        'fmt': 'json',
      },
    );
    final releases = [
      for (final release in response.data?['releases'] as List? ?? const [])
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
