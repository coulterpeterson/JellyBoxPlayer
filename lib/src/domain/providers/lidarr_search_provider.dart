import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/lidarr/deezer_client.dart';
import 'package:jplayer/src/core/lidarr/lidarr_client.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/core/lidarr/musicbrainz_client.dart';
import 'package:jplayer/src/data/providers/search_provider.dart';
import 'package:jplayer/src/domain/providers/lidarr_account_provider.dart';

final musicBrainzClientProvider = Provider<MusicBrainzClient>(
  (ref) => MusicBrainzClient(),
);

final deezerClientProvider = Provider<DeezerClient>((ref) => DeezerClient());

String _term(Ref ref) => ref.watch(searchProvider)?.trim() ?? '';

typedef LidarrCatalogResults = ({
  List<LidarrArtist> artists,
  List<CatalogAlbum> albums,
});

/// Artists and albums Lidarr can fetch for the current search: Lidarr's
/// own search, plus MusicBrainz for albums it misses (soundtracks,
/// Various Artists releases).
final lidarrCatalogSearchProvider =
    FutureProvider.autoDispose<LidarrCatalogResults>((ref) async {
      final client = ref.watch(lidarrClientProvider);
      final term = _term(ref);
      if (client == null || term.length < 2) {
        return (
          artists: const <LidarrArtist>[],
          albums: const <CatalogAlbum>[],
        );
      }
      final lidarrSearch = client.search(term);
      final brainz = ref
          .read(musicBrainzClientProvider)
          .searchReleaseGroups(term)
          .catchError((Object error) {
            debugPrint('[Lidarr] MusicBrainz album search failed: $error');
            return <CatalogAlbum>[];
          });
      final lidarr = await lidarrSearch;
      final albums = <String, CatalogAlbum>{
        for (final album in lidarr.albums)
          album.foreignAlbumId: CatalogAlbum.fromLidarr(album),
      };
      for (final album in await brainz) {
        albums.putIfAbsent(album.releaseGroupId, () => album);
      }
      debugPrint(
        '[Lidarr] search "$term": ${lidarr.artists.length} artists, '
        '${lidarr.albums.length} Lidarr + ${albums.length - lidarr.albums.length} '
        'MusicBrainz albums',
      );
      return (
        artists: lidarr.artists.take(20).toList(),
        albums: albums.values.take(40).toList(),
      );
    });

/// Songs for the current search, ranked by popularity on Deezer.
final lidarrSongSearchProvider = FutureProvider.autoDispose<List<CatalogSong>>((
  ref,
) async {
  if (ref.watch(lidarrClientProvider) == null) return const [];
  final term = _term(ref);
  if (term.length < 2) return const [];
  try {
    return await ref.read(deezerClientProvider).searchTracks(term);
  } on Object catch (error) {
    debugPrint('[Lidarr] Deezer song search failed: $error');
    return const [];
  }
});

/// The albums that contain [song], best match first.
final songSourceProvider = FutureProvider.autoDispose
    .family<SongSource, CatalogSong>((ref, song) async {
      final brainz = ref.read(musicBrainzClientProvider);
      var source = const SongSource(albums: [], recordingIds: {});
      var isrc = song.isrc;
      if (isrc == null && song.deezerId != null) {
        isrc = await ref.read(deezerClientProvider).isrcOf(song.deezerId!);
      }
      if (isrc != null) source = await brainz.songByIsrc(isrc);
      if (source.albums.isEmpty) {
        source = await brainz.songByName(song.title, song.artistName);
      }
      final albums = [...source.albums]
        ..sort((a, b) => compareSongAlbums(a, b, preferTitle: song.albumTitle));
      debugPrint(
        '[Lidarr] "${song.title}" is on ${albums.length} albums; best: '
        '${albums.firstOrNull?.title} (${albums.firstOrNull?.typeLabel})',
      );
      return SongSource(albums: albums, recordingIds: source.recordingIds);
    });

/// An artist's albums: Lidarr's list when it tracks the artist, otherwise
/// MusicBrainz's discography.
final lidarrArtistAlbumsProvider = FutureProvider.autoDispose
    .family<List<CatalogAlbum>, LidarrArtist>((ref, artist) async {
      final client = ref.watch(lidarrClientProvider);
      if (client != null && artist.isInLidarr) {
        final albums = await client.artistAlbums(artist.id);
        return [for (final album in albums) CatalogAlbum.fromLidarr(album)]
          ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      }
      final albums = await ref
          .read(musicBrainzClientProvider)
          .artistReleaseGroups(artist.foreignArtistId);
      return albums..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    });

/// Turns a search result into the album Lidarr would add.
Future<LidarrAlbum?> resolveCatalogAlbum(
  LidarrClient client,
  CatalogAlbum album,
) async => album.lidarr ?? await client.lookupAlbum(album.releaseGroupId);

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

typedef LookingForEntry = ({LidarrAlbum album, LidarrQueueItem? queued});

/// Albums Lidarr is monitoring that have no files yet, with their queue
/// entry when Lidarr is downloading (or stuck importing) one. Refreshes
/// every couple of minutes while shown.
final lidarrLookingForProvider =
    FutureProvider.autoDispose<List<LookingForEntry>>((ref) async {
      final client = ref.watch(lidarrClientProvider);
      if (client == null) return const [];
      final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
      final results = await Future.wait([
        client.wantedMissing(),
        client.queue(),
      ]);
      final missing = results[0] as List<LidarrAlbum>;
      final queue = {
        for (final item in results[1] as List<LidarrQueueItem>)
          item.albumId: item,
      };
      return [
        for (final album in missing)
          if (album.trackFileCount == 0)
            (album: album, queued: queue[album.id]),
      ];
    });
