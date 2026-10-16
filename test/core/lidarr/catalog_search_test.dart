import 'package:flutter_test/flutter_test.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/core/lidarr/musicbrainz_client.dart';

CatalogAlbum _album(
  String id, {
  String? type,
  List<String> secondary = const [],
  int? year,
  String? title,
}) => CatalogAlbum(
  releaseGroupId: id,
  title: title ?? id,
  artistName: 'Billy Idol',
  primaryType: type,
  secondaryTypes: secondary,
  year: year,
);

void main() {
  group('compareSongAlbums', () {
    test('- prefers the studio album, then EP, then single', () {
      final albums = [
        _album('single', type: 'Single', year: 1980),
        _album('compilation', type: 'Album', secondary: ['Compilation']),
        _album('ep', type: 'EP', year: 1981),
        _album('album', type: 'Album', year: 1982),
        _album('live', type: 'Album', secondary: ['Live'], year: 1979),
      ]..sort(compareSongAlbums);

      final ids = [for (final a in albums) a.releaseGroupId];
      expect(ids.take(3), ['album', 'ep', 'single']);
      expect(ids.skip(3), unorderedEquals(['compilation', 'live']));
    });

    test('- breaks ties by the album Deezer named, then the earliest', () {
      final albums = [
        _album('later', type: 'Album', year: 1990),
        _album('earlier', type: 'Album', year: 1985),
        _album('named', type: 'Album', year: 1999, title: 'Rebel Yell'),
      ]..sort((a, b) => compareSongAlbums(a, b, preferTitle: 'Rebel Yell'));

      expect(
        [for (final a in albums) a.releaseGroupId],
        [
          'named',
          'earlier',
          'later',
        ],
      );
    });
  });

  test('MusicBrainzClient.escape escapes Lucene syntax', () {
    expect(
      MusicBrainzClient.escape('AC/DC: Back (in) Black!'),
      r'AC\/DC\: Back \(in\) Black\!',
    );
  });
}
