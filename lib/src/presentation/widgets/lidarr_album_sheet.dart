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
  try {
    final request = await ref
        .read(lidarrRequestsProvider.notifier)
        .request(
          album: album,
          action: action,
          wanted: wanted == null || wanted.isEmpty ? null : wanted,
          playlist: playlist,
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

Future<void> showLidarrAlbumSheet(BuildContext context, LidarrAlbum album) =>
    showModalBottomSheet<void>(
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
        builder: (context, controller) =>
            LidarrAlbumSheet(album: album, scrollController: controller),
      ),
    );

class LidarrAlbumSheet extends ConsumerStatefulWidget {
  const LidarrAlbumSheet({
    required this.album,
    this.scrollController,
    super.key,
  });

  final LidarrAlbum album;
  final ScrollController? scrollController;

  @override
  ConsumerState<LidarrAlbumSheet> createState() => _LidarrAlbumSheetState();
}

class _LidarrAlbumSheetState extends ConsumerState<LidarrAlbumSheet> {
  final _selected = <int>{};
  var _busy = false;

  LidarrAlbum get album => widget.album;

  Future<void> _run(LidarrAction action, List<LidarrTrack> tracks) async {
    if (_busy) return;
    setState(() => _busy = true);
    final wanted = _selected.isEmpty
        ? null
        : [for (final index in _selected.toList()..sort()) tracks[index]];
    final navigator = Navigator.of(context);
    await requestFromLidarr(context, ref, album, action, wanted: wanted);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onPrimary.withValues(alpha: 0.6);
    final tracks = ref.watch(lidarrAlbumTracksProvider(album));
    final trackList = tracks.valueOrNull ?? const <LidarrTrack>[];
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
  Widget build(BuildContext context) {
    final url = album.coverUrl;
    final fallback = Image.asset(
      Images.album,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
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
