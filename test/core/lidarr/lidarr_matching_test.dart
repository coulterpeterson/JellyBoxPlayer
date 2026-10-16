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
}
