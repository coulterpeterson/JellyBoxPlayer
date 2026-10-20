import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/resources/resources.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/core/enums/download_status.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/widgets/album_view.dart';
import 'package:jplayer/src/presentation/widgets/context_menu.dart';
import 'package:jplayer/src/presentation/widgets/lidarr_album_sheet.dart';
import 'package:jplayer/src/presentation/widgets/hover_icon_button.dart';
import 'package:jplayer/src/providers/image_service_provider.dart';

/// A dimmed album card with a progress ring, for a download that is still
/// on its way to this device.
class PendingDownloadCard extends ConsumerWidget {
  const PendingDownloadCard({required this.item, super.key});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSong = item.kind == ItemKind.song;
    final task = isSong ? ref.watch(songDownloadTaskProvider(item.id)) : null;
    final collectionProgress = isSong
        ? null
        : ref.watch(downloadProgressProvider(item.id));

    Widget ring(double? progress) => _DimmedCover(
      image: ref.read(imageServiceProvider).itemImage(item),
      progress: progress,
    );

    return AlbumView(
      album: item,
      alignTextStart: true,
      showDownloadBadge: false,
      subtitle: switch (item.kind) {
        ItemKind.song => 'Song • Downloading…',
        ItemKind.playlist => 'Playlist • Downloading…',
        _ => '${item.albumArtist ?? 'Album'} • Downloading…',
      },
      coverOverride: task == null
          ? ring(collectionProgress)
          : ValueListenableBuilder<double?>(
              valueListenable: task.progress,
              builder: (context, progress, _) => ValueListenableBuilder(
                valueListenable: task.status,
                builder: (context, status, _) => ring(
                  status == DownloadStatus.downloading ? progress : null,
                ),
              ),
            ),
      trailing: isSong
          ? null
          : _CancelButton(
              tooltip: 'Cancel download',
              onPressed: () {
                final manager = ref.read(downloadManagerProvider);
                if (item.kind == ItemKind.playlist) {
                  manager.deletePlaylist(item.id).ignore();
                } else {
                  manager.deleteAlbum(item.id).ignore();
                }
              },
            ),
    );
  }
}

/// A JellyBox request to Lidarr: a progress ring while it downloads, and
/// the "Looking for" look while nothing is available.
class LidarrRequestCard extends ConsumerWidget {
  const LidarrRequestCard({required this.request, super.key});

  final LidarrRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(lidarrRequestsProvider.notifier);
    if (request.stage == LidarrStage.searching) {
      return _LidarrAlbumStatusCard(
        albumId: request.lidarrAlbumId,
        title: request.displayName,
        artistName: request.artistName,
        coverUrl: request.coverUrl,
        status: request.message ?? 'Nothing available yet',
        onStopped: () => notifier.dismiss(request.id),
      );
    }
    final failed = request.stage == LidarrStage.failed;
    final stuck = request.isStuck;
    final url = request.coverUrl;
    final ImageProvider image = url == null
        ? const AssetImage(Images.album)
        : NetworkImage(url);
    return AlbumView(
      album: LibraryItem(
        id: request.id,
        name: request.displayName,
        kind: ItemKind.album,
        albumArtist: request.artistName,
      ),
      alignTextStart: true,
      showDownloadBadge: false,
      subtitle: request.statusLabel,
      coverOverride: _DimmedCover(
        image: image,
        progress: request.stage == LidarrStage.downloading
            ? request.progress
            : null,
        ring: !failed && !stuck,
        icon: failed || stuck
            ? Icons.warning_amber_rounded
            : Icons.cloud_download_outlined,
      ),
      trailing: _CancelButton(
        tooltip: failed ? 'Dismiss' : 'Stop tracking this request',
        onPressed: () => notifier.dismiss(request.id),
      ),
    );
  }
}

/// An album Lidarr is monitoring that has no files yet.
class LookingForCard extends StatelessWidget {
  const LookingForCard({required this.entry, super.key});

  final LookingForEntry entry;

  @override
  Widget build(BuildContext context) {
    final album = entry.album;
    final queued = entry.queued;
    final stuckReason = queued == null || !queued.isStuckImporting
        ? null
        : queued.statusMessages.firstOrNull ??
              'Downloaded, waiting for Lidarr to import it';
    return _LidarrAlbumStatusCard(
      albumId: album.id,
      title: album.title,
      artistName: album.artistName,
      coverUrl: album.coverUrl,
      album: album,
      status:
          stuckReason ??
          switch (queued?.progress) {
            null when queued != null => 'Downloading…',
            final double progress => 'Downloading ${(progress * 100).round()}%',
            _ => 'Nothing available yet',
          },
      downloading: queued != null && stuckReason == null,
      progress: queued?.progress,
      stuck: stuckReason != null,
    );
  }
}

class _LidarrAlbumStatusCard extends ConsumerWidget {
  const _LidarrAlbumStatusCard({
    required this.albumId,
    required this.title,
    required this.artistName,
    required this.coverUrl,
    required this.status,
    this.album,
    this.downloading = false,
    this.stuck = false,
    this.progress,
    this.onStopped,
  });

  final int albumId;
  final String title;
  final String artistName;
  final String? coverUrl;
  final String status;
  final LidarrAlbum? album;
  final bool downloading;
  final bool stuck;
  final double? progress;
  final VoidCallback? onStopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = coverUrl;
    final ImageProvider image = url == null
        ? const AssetImage(Images.album)
        : NetworkImage(url);

    void snack(String message) => ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));

    Future<void> openTracks(BuildContext context) async {
      final client = ref.read(lidarrClientProvider);
      if (client == null) return;
      final resolved = album ?? await client.album(albumId);
      if (context.mounted) await showLidarrAlbumSheet(context, resolved);
    }

    List<ContextMenuAction> actions(BuildContext context) => [
      ContextMenuAction(
        entry: ContextMenuEntry.requestFromLidarr,
        icon: const Icon(Icons.search),
        label: const Text('Search again'),
        run: () async {
          final client = ref.read(lidarrClientProvider);
          if (client == null) return;
          await client.searchAlbum(albumId);
          snack('Asked Lidarr to search for "$title" again');
        },
      ),
      ContextMenuAction(
        entry: ContextMenuEntry.selectSongs,
        icon: const Icon(Icons.checklist),
        label: const Text('Choose songs…'),
        run: () => openTracks(context),
      ),
      ContextMenuAction(
        entry: ContextMenuEntry.stopLooking,
        icon: const Icon(Icons.close),
        label: const Text('Stop looking'),
        run: () async {
          final client = ref.read(lidarrClientProvider);
          if (client == null) return;
          await client.setMonitored([albumId], monitored: false);
          onStopped?.call();
          ref.invalidate(lidarrLookingForProvider);
          snack('Lidarr stopped looking for "$title"');
        },
      ),
    ];

    return AlbumView(
      album: LibraryItem(
        id: 'lidarr-$albumId',
        name: title,
        kind: ItemKind.album,
        albumArtist: artistName,
      ),
      alignTextStart: true,
      showDownloadBadge: false,
      subtitle: [if (artistName.isNotEmpty) artistName, status].join(' • '),
      onTap: (_) => openTracks(context),
      optionsBuilder: actions,
      coverOverride: _DimmedCover(
        image: image,
        progress: downloading ? progress : null,
        ring: downloading,
        icon: stuck
            ? Icons.warning_amber_rounded
            : downloading
            ? Icons.cloud_download_outlined
            : Icons.manage_search,
      ),
      trailing: ContextMenuButton(actionsBuilder: actions),
    );
  }
}

class _DimmedCover extends StatelessWidget {
  const _DimmedCover({
    required this.image,
    this.progress,
    this.icon,
    this.ring = true,
  });

  final ImageProvider image;
  final double? progress;
  final IconData? icon;

  /// False for a still icon instead of a progress ring.
  final bool ring;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.35,
            child: Image(
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Image.asset(Images.album, fit: BoxFit.cover),
            ),
          ),
          Center(
            child: SizedBox.square(
              dimension: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (ring)
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        color: Colors.white,
                      ),
                    ),
                  if (progress != null)
                    Text(
                      '${(progress! * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (icon case final icon?)
                    Icon(icon, size: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => HoverIconButton(
    onPressed: onPressed,
    style: const ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: WidgetStatePropertyAll(Size.zero),
      visualDensity: VisualDensity.compact,
    ),
    tooltip: tooltip,
    iconSize: 20,
    icon: const Icon(Icons.close),
  );
}
