import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/resources/j_player_icons.dart';
import 'package:jplayer/src/data/providers/providers.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/utils/utils.dart';
import 'package:jplayer/src/presentation/widgets/context_menu.dart';
import 'package:jplayer/src/presentation/widgets/playlist_picker_sheet.dart';
import 'package:jplayer/src/providers/connectivity_provider.dart';

/// The songs picked in a track list's select mode, which starts with a long
/// press on a track.
class SongSelectionController extends ChangeNotifier {
  final _selected = <String, LibraryItem>{};
  var _active = false;

  bool get isActive => _active;

  List<LibraryItem> get selected => _selected.values.toList();

  int get count => _selected.length;

  bool isSelected(String id) => _selected.containsKey(id);

  void start(LibraryItem song) {
    _active = true;
    _selected[song.id] = song;
    notifyListeners();
  }

  void toggle(LibraryItem song) {
    if (_selected.remove(song.id) == null) _selected[song.id] = song;
    notifyListeners();
  }

  void selectAll(Iterable<LibraryItem> songs) {
    for (final song in songs) {
      _selected[song.id] = song;
    }
    notifyListeners();
  }

  void deselectAll() {
    _selected.clear();
    notifyListeners();
  }

  void end() {
    _active = false;
    _selected.clear();
    notifyListeners();
  }
}

class SongSelectionScope extends InheritedNotifier<SongSelectionController> {
  const SongSelectionScope({
    required SongSelectionController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SongSelectionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SongSelectionScope>()
      ?.notifier;
}

/// Enables select mode for the track lists in [child] and shows the bulk
/// actions bar over the top of the page while songs are selected.
class SongSelectionHost extends ConsumerStatefulWidget {
  const SongSelectionHost({
    required this.child,
    required this.songs,
    this.onDeleted,
    this.onChanged,
    this.extraActions,
    super.key,
  });

  final Widget child;

  /// Every song on the page, for "Select all".
  final List<LibraryItem> Function() songs;

  /// Called with the songs that were deleted from the server.
  final void Function(List<LibraryItem> deleted)? onDeleted;

  /// Called after an action that changes the songs, e.g. favouriting.
  final VoidCallback? onChanged;

  /// Page specific actions, e.g. removing songs from a playlist.
  final List<ContextMenuAction> Function(
    List<LibraryItem> selected,
    VoidCallback done,
  )?
  extraActions;

  @override
  ConsumerState<SongSelectionHost> createState() => _SongSelectionHostState();
}

class _SongSelectionHostState extends ConsumerState<SongSelectionHost> {
  final _controller = SongSelectionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _guardOffline() {
    if (!ref.read(isOfflineProvider)) return false;
    _snack('Not available offline');
    return true;
  }

  String _label(int count) => count == 1 ? '1 song' : '$count songs';

  List<ContextMenuAction> _actions() {
    final selected = _controller.selected;
    final allFavourite = selected.every((song) => song.userData.isFavorite);
    final canDelete =
        ref.read(serverCapabilitiesProvider).deleteItems && selected.isNotEmpty;
    void done() => _controller.end();

    return [
      ContextMenuAction(
        entry: ContextMenuEntry.playNext,
        icon: const Icon(Icons.playlist_play),
        label: const Text('Play next'),
        run: () async {
          final queued = await ref
              .read(playbackProvider.notifier)
              .playNextAll(selected);
          done();
          _snack(queued ? 'Playing next' : "Couldn't queue the songs");
        },
      ),
      ContextMenuAction(
        entry: ContextMenuEntry.addToQueue,
        icon: const Icon(Icons.playlist_add),
        label: const Text('Add to queue'),
        run: () async {
          final queued = await ref
              .read(playbackProvider.notifier)
              .addAllToQueue(selected);
          done();
          _snack(queued ? 'Added to queue' : "Couldn't queue the songs");
        },
      ),
      ContextMenuAction(
        entry: ContextMenuEntry.addToPlaylist,
        icon: const Icon(CupertinoIcons.text_badge_plus),
        label: const Text('Add to playlist'),
        run: () async {
          if (_guardOffline()) return;
          final playlist = await showPlaylistPicker(
            context,
            isDesktop: DeviceType.fromScreenSize(
              MediaQuery.sizeOf(context),
            ).isDesktop,
          );
          if (playlist == null || !mounted) return;
          try {
            await ref
                .read(mediaServerClientProvider)
                .addPlaylistItems(
                  playlistId: playlist.id,
                  itemIds: [for (final song in selected) song.id],
                );
            ref.read(downloadSyncProvider).syncPlaylist(playlist.id);
            done();
            _snack('Added ${_label(selected.length)} to ${playlist.name}');
          } on Object {
            _snack("Couldn't add the songs to ${playlist.name}");
          }
        },
      ),
      ContextMenuAction(
        entry: ContextMenuEntry.download,
        icon: const Icon(JPlayer.download),
        label: const Text('Download'),
        run: () async {
          if (_guardOffline()) return;
          final manager = ref.read(downloadManagerProvider);
          final database = ref.read(downloadDatabaseProvider);
          done();
          _snack('Downloading ${_label(selected.length)}');
          for (final song in selected) {
            if (await database.isSongDownloaded(song.id)) continue;
            await manager.downloadSong(song);
          }
        },
      ),
      ContextMenuAction(
        entry: ContextMenuEntry.like,
        icon: Icon(allFavourite ? Icons.favorite : Icons.favorite_border),
        label: Text(
          allFavourite ? 'Remove from favourites' : 'Add to favourites',
        ),
        run: () async {
          if (_guardOffline()) return;
          final client = ref.read(mediaServerClientProvider);
          final favourite = !allFavourite;
          try {
            for (final song in selected) {
              if (song.userData.isFavorite == favourite) continue;
              await client.setFavorite(song.id, favorite: favourite);
            }
          } on Object {
            _snack("Couldn't update favourites");
          }
          ref.read(favouritesChangedProvider.notifier).state++;
          ref.invalidate(favouriteSongsProvider);
          done();
          widget.onChanged?.call();
        },
      ),
      ...?widget.extraActions?.call(selected, done),
      if (canDelete)
        ContextMenuAction(
          entry: ContextMenuEntry.deleteFromServer,
          icon: const Icon(
            Icons.delete_forever_outlined,
            color: Colors.redAccent,
          ),
          label: const Text(
            'Delete from server',
            style: TextStyle(color: Colors.redAccent),
          ),
          run: () async {
            final deleted = await confirmAndDeleteFromServer(
              context,
              ref,
              selected,
            );
            if (deleted.isEmpty) return;
            done();
            widget.onDeleted?.call(deleted);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => SongSelectionScope(
    controller: _controller,
    child: ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => PopScope(
        canPop: !_controller.isActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _controller.end();
        },
        child: Stack(
          children: [
            child!,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _controller.isActive ? _bar(context) : null,
              ),
            ),
          ],
        ),
      ),
      child: widget.child,
    ),
  );

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final count = _controller.count;
    final all = widget.songs();
    final allSelected = all.isNotEmpty && count >= all.length;
    return Material(
      color: Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.18),
        theme.scaffoldBackgroundColor,
      ),
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Done',
                onPressed: _controller.end,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  count == 0 ? 'Select songs' : '$count selected',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => allSelected
                    ? _controller.deselectAll()
                    : _controller.selectAll(all),
                child: Text(allSelected ? 'Select none' : 'Select all'),
              ),
              IconButton(
                tooltip: 'Actions',
                onPressed: count == 0
                    ? null
                    : () => unawaited(
                        showContextMenuSheet(context, actions: _actions()),
                      ),
                icon: const Icon(Icons.more_vert),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// The check circle shown next to each track in select mode.
class SelectionCheck extends StatelessWidget {
  const SelectionCheck({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          key: ValueKey(selected),
          size: 24,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onPrimary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

void startSongSelection(BuildContext context, LibraryItem song) {
  final controller = SongSelectionScope.maybeOf(context);
  if (controller == null) return;
  HapticFeedback.selectionClick().ignore();
  controller.isActive ? controller.toggle(song) : controller.start(song);
}
