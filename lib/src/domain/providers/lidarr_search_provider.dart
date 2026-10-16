import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/core/lidarr/musicbrainz_client.dart';
import 'package:jplayer/src/data/providers/search_provider.dart';
import 'package:jplayer/src/domain/providers/lidarr_account_provider.dart';

/// Albums Lidarr can fetch for the current search term.
final lidarrSearchProvider = FutureProvider.autoDispose<List<LidarrAlbum>>((
  ref,
) async {
  final client = ref.watch(lidarrClientProvider);
  final term = ref.watch(searchProvider)?.trim() ?? '';
  if (client == null || term.length < 2) return const [];
  final albums = await client.searchAlbums(term);
  return albums.take(30).toList();
});

final musicBrainzClientProvider = Provider<MusicBrainzClient>(
  (ref) => MusicBrainzClient(),
);

/// The track listing of a Lidarr album: Lidarr's own when it already tracks
/// the album, otherwise MusicBrainz's.
final lidarrAlbumTracksProvider = FutureProvider.autoDispose
    .family<List<LidarrTrack>, LidarrAlbum>((ref, album) async {
      final client = ref.watch(lidarrClientProvider);
      if (client != null && album.isInLidarr) {
        final tracks = await client.tracks(album.id);
        if (tracks.isNotEmpty) return tracks;
      }
      if (album.foreignAlbumId.isEmpty) return const [];
      return ref
          .read(musicBrainzClientProvider)
          .releaseGroupTracks(album.foreignAlbumId);
    });
