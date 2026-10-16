import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/data/providers/providers.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/utils/refresh_home_sections.dart';
import 'package:jplayer/src/presentation/widgets/adaptive_dialog_action.dart';
import 'package:jplayer/src/providers/connectivity_provider.dart';

/// Whether the connected server lets this app delete library items.
bool canDeleteFromServer(WidgetRef ref, LibraryItem item) =>
    (item.kind == ItemKind.song || item.kind == ItemKind.album) &&
    ref.read(serverCapabilitiesProvider).deleteItems;

/// Asks before permanently deleting [items] from the media server, then
/// deletes them. Returns the items that were deleted.
Future<List<LibraryItem>> confirmAndDeleteFromServer(
  BuildContext context,
  WidgetRef ref,
  List<LibraryItem> items,
) async {
  if (items.isEmpty) return const [];
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (ref.read(isOfflineProvider)) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Not available offline')),
    );
    return const [];
  }
  final what = items.length == 1
      ? '"${items.first.name}"'
      : '${items.length} ${items.every((i) => i.kind == ItemKind.song) ? 'songs' : 'items'}';
  final confirmed = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text('Delete $what from the server?', textAlign: TextAlign.center),
      content: const Text(
        'The files are permanently deleted from your media server for '
        'everyone. This cannot be undone.',
        textAlign: TextAlign.center,
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(true),
          isDestructiveAction: true,
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return const [];

  final deleted = await deleteFromServer(ref, items);
  final failed = items.length - deleted.length;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        failed == 0
            ? 'Deleted $what from the server'
            : deleted.isEmpty
            ? "Couldn't delete $what. Your server account may not be "
                  'allowed to delete media.'
            : 'Deleted ${deleted.length}, $failed failed',
      ),
    ),
  );
  return deleted;
}

Future<List<LibraryItem>> deleteFromServer(
  WidgetRef ref,
  List<LibraryItem> items,
) async {
  final client = ref.read(mediaServerClientProvider);
  final manager = ref.read(downloadManagerProvider);
  final database = ref.read(downloadDatabaseProvider);
  final deleted = <LibraryItem>[];
  final albumIds = <String>{};
  for (final item in items) {
    try {
      await client.deleteItem(item.id);
      deleted.add(item);
    } on Object catch (error) {
      debugPrint('[Delete] ${item.name} failed: $error');
      continue;
    }
    try {
      if (item.kind == ItemKind.album) {
        albumIds.add(item.id);
        if (await database.isAlbumDownloaded(item.id)) {
          await manager.deleteAlbum(item.id);
        }
      } else {
        if (item.albumId case final albumId?) albumIds.add(albumId);
        if (await database.isSongDownloaded(item.id)) {
          await manager.deleteSong(item.id);
        }
      }
    } on Object catch (error) {
      debugPrint('[Delete] removing the download of ${item.name}: $error');
    }
  }
  if (deleted.isNotEmpty) {
    await _unmonitorInLidarr(ref, items, albumIds);
    ref
      ..invalidate(itemListProvider)
      ..refreshHomeSections();
  }
  return deleted;
}

/// Stops Lidarr from fetching deleted albums or songs again.
Future<void> _unmonitorInLidarr(
  WidgetRef ref,
  List<LibraryItem> items,
  Set<String> albumIds,
) async {
  final lidarr = ref.read(lidarrClientProvider);
  if (lidarr == null || albumIds.isEmpty) return;
  final client = ref.read(mediaServerClientProvider);
  final ids = <int>{};
  for (final albumId in albumIds) {
    try {
      final known = items.where((i) => i.id == albumId).firstOrNull;
      final album =
          known ?? await client.getItem(albumId, kind: ItemKind.album);
      final groupId =
          album.externalIds[ExternalIdProvider.musicBrainzReleaseGroup];
      if (groupId == null) continue;
      final match = await lidarr.albumByForeignId(groupId);
      if (match != null && match.monitored) ids.add(match.id);
    } on Object catch (error) {
      debugPrint('[Delete] Lidarr unmonitor failed for $albumId: $error');
    }
  }
  if (ids.isEmpty) return;
  try {
    await lidarr.setMonitored(ids.toList(), monitored: false);
  } on Object catch (error) {
    debugPrint('[Delete] Lidarr unmonitor failed: $error');
  }
}
