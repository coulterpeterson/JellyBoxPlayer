import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/resources/resources.dart';
import 'package:jplayer/src/core/enums/download_status.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/widgets/album_view.dart';
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

/// The same placeholder for an album Lidarr is still fetching.
class LidarrRequestCard extends ConsumerWidget {
  const LidarrRequestCard({required this.request, super.key});

  final LidarrRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = request.stage == LidarrStage.failed;
    final url = request.coverUrl;
    final ImageProvider image = url == null
        ? const AssetImage(Images.album)
        : NetworkImage(url);
    final progress = switch (request.stage) {
      LidarrStage.downloading => request.progress,
      LidarrStage.searching ||
      LidarrStage.waitingForServer ||
      LidarrStage.downloadingToDevice => null,
      LidarrStage.done => 1.0,
      LidarrStage.failed => 0.0,
    };

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
        progress: progress,
        icon: failed ? Icons.error_outline : Icons.cloud_download_outlined,
      ),
      trailing: _CancelButton(
        tooltip: failed ? 'Dismiss' : 'Stop tracking this request',
        onPressed: () =>
            ref.read(lidarrRequestsProvider.notifier).dismiss(request.id),
      ),
    );
  }
}

class _DimmedCover extends StatelessWidget {
  const _DimmedCover({required this.image, this.progress, this.icon});

  final ImageProvider image;
  final double? progress;
  final IconData? icon;

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
