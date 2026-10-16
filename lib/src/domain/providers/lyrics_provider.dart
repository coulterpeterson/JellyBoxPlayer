import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/lyrics/lrclib_client.dart';
import 'package:jplayer/src/data/providers/providers.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/player_bar_provider.dart';
import 'package:jplayer/src/domain/providers/studio_mode_provider.dart';
import 'package:jplayer/src/providers/connectivity_provider.dart';

final lrclibClientProvider = Provider<LrclibClient>((ref) => LrclibClient());

/// Lyrics for a song: the server's own lyrics when it has any, otherwise
/// a lookup on LRCLIB, an open lyrics database that needs no account.
final lyricsProvider = FutureProviderFamily<Lyrics?, String>((
  ref,
  itemId,
) async {
  if (ref.watch(isOfflineProvider)) return null;
  final client = ref.watch(mediaServerClientProvider);

  if (ref.watch(serverCapabilitiesProvider).lyrics) {
    try {
      final lyrics = await client.getLyrics(itemId);
      if (lyrics != null && lyrics.lines.isNotEmpty) return lyrics;
    } on Object catch (error) {
      debugPrint('[Lyrics] server lyrics failed for $itemId: $error');
    }
  }

  final LibraryItem song;
  try {
    song = await client.getItem(itemId, kind: ItemKind.song);
  } on Object {
    return null;
  }
  try {
    return await ref.read(lrclibClientProvider).lyricsFor(song);
  } on Object catch (error) {
    debugPrint('[Lyrics] LRCLIB lookup failed for ${song.name}: $error');
    return null;
  }
});

final lyricsVisibleProvider = StateProvider<bool>((ref) => false);

final currentSongHasLyricsProvider = Provider<bool>((ref) {
  final song = ref.watch(barSongProvider);
  if (song == null) return false;
  final lyrics = ref.watch(lyricsProvider(song.id));
  if (!lyrics.hasValue) return song.hasLyrics;
  return lyrics.value?.lines.isNotEmpty ?? false;
});

final lyricsShownProvider = Provider<bool>((ref) {
  if (!ref.watch(lyricsVisibleProvider)) return false;
  if (ref.watch(studioModeVisibleProvider)) return false;
  return ref.watch(currentSongHasLyricsProvider);
});
