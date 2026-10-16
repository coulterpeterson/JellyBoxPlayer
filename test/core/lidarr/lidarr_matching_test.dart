import 'package:flutter_test/flutter_test.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/lidarr_requests_provider.dart';

void main() {
  group('normalizeTitle', () {
    test('- ignores case, punctuation and bracketed suffixes', () {
      expect(
        normalizeTitle('Hearts & Minds (2008 Remaster)'),
        normalizeTitle('hearts and minds'),
      );
    });
  });

  group('WantedTrack', () {
    const wanted = WantedTrack(title: 'Buddy Holly', recordingId: 'rec-1');

    test('- matches a Lidarr track by recording id', () {
      expect(
        wanted.matchesTrack(
          const LidarrTrack(
            title: 'Something else',
            number: 1,
            recordingId: 'rec-1',
          ),
        ),
        isTrue,
      );
    });

    test('- matches a Lidarr track by title', () {
      expect(
        wanted.matchesTrack(
          const LidarrTrack(title: 'Buddy Holly!', number: 4),
        ),
        isTrue,
      );
    });

    test('- leaves other tracks alone so they can be trimmed', () {
      expect(
        wanted.matchesTrack(
          const LidarrTrack(title: 'Say It Ain\'t So', number: 7),
        ),
        isFalse,
      );
    });

    test('- finds the song on the media server', () {
      expect(
        wanted.matchesSong(
          const LibraryItem(id: 's', name: 'Buddy Holly', kind: ItemKind.song),
        ),
        isTrue,
      );
    });
  });

  test('LidarrRequest survives a JSON round trip', () {
    final request = LidarrRequest(
      id: '1',
      lidarrAlbumId: 5,
      foreignAlbumId: 'rg',
      albumTitle: 'Weezer',
      artistName: 'Weezer',
      action: LidarrAction.playlist,
      createdAt: DateTime(2026),
      playlistId: 'p',
      wanted: const [WantedTrack(title: 'Buddy Holly')],
    );
    final copy = LidarrRequest.fromJson(request.toJson());
    expect(copy.action, LidarrAction.playlist);
    expect(copy.wanted?.single.title, 'Buddy Holly');
    expect(copy.displayName, 'Buddy Holly');
  });

  group('rerouting', () {
    test('- editionKey tells editions apart, normalizeTitle does not', () {
      expect(
        editionKey('Synchronicity (Super Deluxe Edition)'),
        isNot(editionKey('Synchronicity')),
      );
      expect(
        editionKey('Synchronicity (Super Deluxe Edition)'),
        editionKey('Synchronicity - Super Deluxe Edition'),
      );
      expect(
        normalizeTitle('Synchronicity (Super Deluxe Edition)'),
        normalizeTitle('Synchronicity'),
      );
    });

    test('- a rerouted request remembers what it tried', () {
      final original = LidarrRequest(
        id: '1',
        lidarrAlbumId: 1072,
        foreignAlbumId: 'rg-original',
        albumTitle: 'Synchronicity',
        artistName: 'The Police',
        action: LidarrAction.download,
        createdAt: DateTime(2026),
        alternatives: const [(releaseGroupId: 'rg-best-of', title: 'Best Of')],
      );
      final deluxe = LidarrAlbum({
        'id': 2001,
        'title': 'Synchronicity (Super Deluxe Edition)',
        'foreignAlbumId': 'rg-deluxe',
        'artist': {'artistName': 'The Police'},
      });

      final moved = original.rerouted(
        to: deluxe,
        wanted: const [WantedTrack(title: 'Every Breath You Take')],
        message: 'Only the deluxe edition is available',
      );
      final restored = LidarrRequest.fromJson(moved.toJson());

      expect(restored.lidarrAlbumId, 2001);
      expect(restored.albumTitle, 'Synchronicity (Super Deluxe Edition)');
      expect(restored.tried, ['rg-original']);
      expect(restored.wanted?.single.title, 'Every Breath You Take');
      expect(restored.alternatives.single.releaseGroupId, 'rg-best-of');
      expect(restored.message, 'Only the deluxe edition is available');
    });
  });
}
