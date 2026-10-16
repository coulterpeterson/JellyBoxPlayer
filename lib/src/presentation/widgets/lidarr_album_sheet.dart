import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/resources/j_player_icons.dart';
import 'package:jplayer/resources/resources.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/utils/utils.dart';
import 'package:jplayer/src/presentation/widgets/playlist_picker_sheet.dart';
import 'package:jplayer/src/presentation/widgets/shimmer.dart';

/// Requests [album] from Lidarr for [action], asking for a playlist first
/// when needed. Pass [wanted] to keep only those songs once it arrives.
Future<void> requestFromLidarr(
  BuildContext context,
  WidgetRef ref,
  LidarrAlbum album,
  LidarrAction action, {
  List<LidarrTrack>? wanted,
  List<CatalogAlbum> alternatives = const [],
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  LibraryItem? playlist;
  if (action == LidarrAction.playlist) {
    final isDesktop = DeviceType.fromScreenSize(
      MediaQuery.sizeOf(context),
    ).isDesktop;
    playlist = await showPlaylistPicker(context, isDesktop: isDesktop);
    if (playlist == null) return;
  }
  messenger?.showSnackBar(
    SnackBar(content: Text('Sending "${album.title}" to Lidarr…')),
  );
  try {
    final request = await ref
        .read(lidarrRequestsProvider.notifier)
        .request(
          album: album,
          action: action,
          wanted: wanted == null || wanted.isEmpty ? null : wanted,
          playlist: playlist,
          alternatives: alternatives,
        );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(switch (action) {
          LidarrAction.library => 'Asked Lidarr for "${request.displayName}"',
          LidarrAction.download =>
            'Downloading "${request.displayName}" once Lidarr has it',
          LidarrAction.playlist =>
            'Adding "${request.displayName}" to ${playlist!.name} '
                'once Lidarr has it',
        }),
      ),
    );
  } on Object catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Lidarr request failed: $error')),
    );
  }
}

Future<void> showLidarrAlbumSheet(
  BuildContext context,
  LidarrAlbum album, {
  SongPick? pick,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Colors.grey[900],
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
  ),
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (context, controller) => LidarrAlbumSheet(
      album: album,
      pick: pick,
      scrollController: controller,
    ),
  ),
);

/// The song the user searched for, to tick in the album's track list, and
/// the other albums it's on.
class SongPick {
  const SongPick({
    required this.title,
    required this.recordingIds,
    this.alternatives = const [],
  });

  final String title;
  final Set<String> recordingIds;
  final List<CatalogAlbum> alternatives;

  bool matches(LidarrTrack track) =>
      (track.recordingId != null && recordingIds.contains(track.recordingId)) ||
      normalizeTitle(track.title) == normalizeTitle(title);
}

class LidarrAlbumSheet extends ConsumerStatefulWidget {
  const LidarrAlbumSheet({
    required this.album,
    this.pick,
    this.scrollController,
    super.key,
  });

  final LidarrAlbum album;
  final SongPick? pick;
  final ScrollController? scrollController;

  @override
  ConsumerState<LidarrAlbumSheet> createState() => _LidarrAlbumSheetState();
}

class _LidarrAlbumSheetState extends ConsumerState<LidarrAlbumSheet> {
  final _selected = <int>{};
  var _busy = false;
  var _picked = false;

  LidarrAlbum get album => widget.album;

  Future<void> _run(LidarrAction action, List<LidarrTrack> tracks) async {
    if (_busy) return;
    setState(() => _busy = true);
    final wanted = _selected.isEmpty
        ? null
        : [for (final index in _selected.toList()..sort()) tracks[index]];
    final navigator = Navigator.of(context);
    await requestFromLidarr(
      context,
      ref,
      album,
      action,
      wanted: wanted,
      alternatives: widget.pick?.alternatives ?? const [],
    );
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onPrimary.withValues(alpha: 0.6);
    final tracks = ref.watch(lidarrAlbumTracksProvider(album));
    final trackList = tracks.valueOrNull ?? const <LidarrTrack>[];
    final pick = widget.pick;
    if (!_picked && pick != null && trackList.isNotEmpty) {
      _picked = true;
      for (final (index, track) in trackList.indexed) {
        if (pick.matches(track)) _selected.add(index);
      }
    }
    final year = album.releaseDate?.year;
    final inLibrary =
        album.isInLidarr &&
        album.trackCount > 0 &&
        album.trackFileCount >= album.trackCount;

    return SafeArea(
      top: false,
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LidarrCover(album: album, size: 96),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(album.artistName, style: TextStyle(color: muted)),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (album.albumType case final type?) type,
                            if (year != null) '$year',
                            if (inLibrary)
                              'On your server'
                            else if (album.trackFileCount > 0)
                              '${album.trackFileCount} of '
                                  '${album.trackCount} songs on your server',
                          ].join(' • '),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 4,
                children: [
                  _action(
                    icon: Icons.library_add_outlined,
                    label: 'Add to library',
                    onPressed: () => _run(LidarrAction.library, trackList),
                  ),
                  _action(
                    icon: JPlayer.download,
                    label: 'Download',
                    onPressed: () => _run(LidarrAction.download, trackList),
                  ),
                  _action(
                    icon: CupertinoIcons.text_badge_plus,
                    label: 'Add to playlist',
                    onPressed: () => _run(LidarrAction.playlist, trackList),
                  ),
                ],
              ),
            ),
          ),
          if (pick != null && pick.alternatives.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _chooseVersion(pick),
                    icon: const Icon(Icons.swap_horiz, size: 20),
                    label: Text(
                      '"${pick.title}" is on ${pick.alternatives.length} '
                      'releases. Choose another',
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _selected.isEmpty
                    ? 'Whole album. Tap songs to only get those; Lidarr '
                          'fetches the album and the other songs are '
                          'deleted afterwards.'
                    : '${_selected.length} of ${trackList.length} songs '
                          'selected. The rest of the album is deleted once '
                          'Lidarr has it.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ),
          if (tracks.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: TextLinesShimmer(count: 6),
              ),
            )
          else if (tracks.hasError || trackList.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Couldn't load the track list, but you can still request "
                  'the whole album.',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: trackList.length,
              itemBuilder: (context, index) {
                final track = trackList[index];
                final selected = _selected.contains(index);
                return CheckboxListTile(
                  value: selected,
                  controlAffinity: ListTileControlAffinity.leading,
                  checkboxShape: const CircleBorder(),
                  dense: true,
                  onChanged: (value) => setState(
                    () => (value ?? false)
                        ? _selected.add(index)
                        : _selected.remove(index),
                  ),
                  title: Text(track.title),
                  subtitle: track.hasFile
                      ? Text(
                          'On your server',
                          style: TextStyle(fontSize: 11, color: muted),
                        )
                      : null,
                  secondary: track.duration > Duration.zero
                      ? Text(
                          _formatDuration(track.duration),
                          style: TextStyle(fontSize: 12, color: muted),
                        )
                      : null,
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Future<void> _chooseVersion(SongPick pick) async {
    final chosen = await showModalBottomSheet<CatalogAlbum>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            for (final album in pick.alternatives)
              ListTile(
                leading: LidarrCoverImage(url: album.coverUrl, size: 44),
                title: Text(album.title),
                subtitle: Text(
                  [
                    album.artistName,
                    if (album.typeLabel.isNotEmpty) album.typeLabel,
                    if (album.year != null) '${album.year}',
                  ].join(' • '),
                ),
                selected: album.releaseGroupId == widget.album.foreignAlbumId,
                onTap: () => Navigator.of(context).pop(album),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final navigator = Navigator.of(context);
    final opened = openCatalogAlbum(context, ref, chosen, pick: pick);
    navigator.pop();
    await opened;
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => TextButton.icon(
    onPressed: _busy ? null : onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    icon: Icon(icon, size: 20),
    label: Text(label),
  );

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class LidarrCover extends StatelessWidget {
  const LidarrCover({required this.album, required this.size, super.key});

  final LidarrAlbum album;
  final double size;

  @override
  Widget build(BuildContext context) =>
      LidarrCoverImage(url: album.coverUrl, size: size);
}

class LidarrCoverImage extends StatelessWidget {
  const LidarrCoverImage({
    required this.url,
    required this.size,
    this.circle = false,
    super.key,
  });

  final String? url;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final fallback = Image.asset(
      Images.album,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size / 2 : 6),
      child: url == null
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// Opens a search result's album, looking it up in Lidarr first if it
/// came from MusicBrainz.
Future<void> openCatalogAlbum(
  BuildContext context,
  WidgetRef ref,
  CatalogAlbum album, {
  SongPick? pick,
}) async {
  final client = ref.read(lidarrClientProvider);
  if (client == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final LidarrAlbum? resolved;
  try {
    resolved = await _withProgress(
      context,
      resolveCatalogAlbum(client, album),
    );
  } on Object catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text("Couldn't look up ${album.title}: $error")),
    );
    return;
  }
  if (resolved == null) {
    messenger?.showSnackBar(
      SnackBar(content: Text("Lidarr doesn't know \"${album.title}\" yet")),
    );
    return;
  }
  if (!context.mounted) return;
  await showLidarrAlbumSheet(context, resolved, pick: pick);
}

/// Finds the best album containing [song] and opens it with the song
/// ticked.
Future<void> openCatalogSong(
  BuildContext context,
  WidgetRef ref,
  CatalogSong song,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final SongSource source;
  try {
    source = await _withProgress(
      context,
      ref.read(songSourceProvider(song).future),
    );
  } on Object catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text("Couldn't find albums for ${song.title}: $error")),
    );
    return;
  }
  if (source.albums.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('No album with "${song.title}" found on MusicBrainz'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await openCatalogAlbum(
    context,
    ref,
    source.albums.first,
    pick: SongPick(
      title: song.title,
      recordingIds: source.recordingIds,
      alternatives: source.albums,
    ),
  );
}

Future<T> _withProgress<T>(BuildContext context, Future<T> future) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var shown = true;
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).whenComplete(() => shown = false),
  );
  try {
    return await future;
  } finally {
    if (shown) navigator.pop();
  }
}
