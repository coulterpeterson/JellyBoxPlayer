import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/resources/j_player_icons.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/utils/utils.dart';
import 'package:jplayer/src/presentation/widgets/album_card_metrics.dart';
import 'package:jplayer/src/presentation/widgets/context_menu.dart';
import 'package:jplayer/src/presentation/widgets/horizontal_scroll_region.dart';
import 'package:jplayer/src/presentation/widgets/lidarr_album_sheet.dart';

/// Search results from Lidarr: albums that can be requested for the server.
List<Widget> lidarrSearchSlivers(
  BuildContext context,
  WidgetRef ref,
  DeviceType device,
) {
  if (ref.watch(lidarrClientProvider) == null) return const [];
  final results = ref.watch(lidarrSearchProvider);
  final albums = results.valueOrNull ?? const <LidarrAlbum>[];
  if (albums.isEmpty && !results.isLoading) return const [];

  final cardWidth = AlbumCardMetrics.width(device);
  final spacing = AlbumCardMetrics.crossAxisSpacing(device);
  return [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Text('Get from Lidarr', style: TextStyle(fontSize: 18)),
            if (results.isLoading) ...[
              const SizedBox(width: 10),
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    ),
    if (albums.isNotEmpty)
      SliverToBoxAdapter(
        child: SizedBox(
          height: AlbumCardMetrics.height(cardWidth, isTablet: device.isTablet),
          child: HorizontalScrollRegion(
            controlsHeight: cardWidth,
            builder: (context, controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: albums.length,
              separatorBuilder: (context, index) => SizedBox(width: spacing),
              itemBuilder: (context, index) => SizedBox(
                width: cardWidth,
                child: LidarrAlbumCard(album: albums[index], width: cardWidth),
              ),
            ),
          ),
        ),
      ),
    SliverToBoxAdapter(child: SizedBox(height: device.isMobile ? 16 : 24)),
  ];
}

List<ContextMenuAction> lidarrAlbumActions(
  BuildContext context,
  WidgetRef ref,
  LidarrAlbum album,
) => [
  ContextMenuAction(
    entry: ContextMenuEntry.selectSongs,
    icon: const Icon(Icons.checklist),
    label: const Text('Choose songs…'),
    run: () => showLidarrAlbumSheet(context, album),
  ),
  ContextMenuAction(
    entry: ContextMenuEntry.requestFromLidarr,
    icon: const Icon(Icons.library_add_outlined),
    label: const Text('Add to library'),
    run: () => requestFromLidarr(context, ref, album, LidarrAction.library),
  ),
  ContextMenuAction(
    entry: ContextMenuEntry.requestFromLidarr,
    icon: const Icon(JPlayer.download),
    label: const Text('Download'),
    run: () => requestFromLidarr(context, ref, album, LidarrAction.download),
  ),
  ContextMenuAction(
    entry: ContextMenuEntry.requestFromLidarr,
    icon: const Icon(CupertinoIcons.text_badge_plus),
    label: const Text('Add to playlist'),
    run: () => requestFromLidarr(context, ref, album, LidarrAction.playlist),
  ),
];

class LidarrAlbumCard extends ConsumerWidget {
  const LidarrAlbumCard({required this.album, required this.width, super.key});

  final LidarrAlbum album;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onPrimary.withValues(alpha: 0.6);
    final inLibrary =
        album.isInLidarr &&
        album.trackCount > 0 &&
        album.trackFileCount >= album.trackCount;
    final year = album.releaseDate?.year;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showLidarrAlbumSheet(context, album),
      onLongPress: () {
        HapticFeedback.mediumImpact().ignore();
        showContextMenuSheet(
          context,
          actions: lidarrAlbumActions(context, ref, album),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              LidarrCover(album: album, size: width),
              if (inLibrary)
                Positioned(
                  top: 6,
                  left: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('In library', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [album.artistName, if (year != null) '$year'].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              ContextMenuButton(
                actionsBuilder: (context) =>
                    lidarrAlbumActions(context, ref, album),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
