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
import 'package:jplayer/src/presentation/widgets/shimmer.dart';

/// Search results from Lidarr: artists, albums and songs that can be
/// requested for the server.
List<Widget> lidarrSearchSlivers(
  BuildContext context,
  WidgetRef ref,
  DeviceType device,
) {
  if (ref.watch(lidarrClientProvider) == null) return const [];
  final catalog = ref.watch(lidarrCatalogSearchProvider);
  final songs = ref.watch(lidarrSongSearchProvider);
  final artists = catalog.valueOrNull?.artists ?? const <LidarrArtist>[];
  final albums = catalog.valueOrNull?.albums ?? const <CatalogAlbum>[];
  final songList = songs.valueOrNull ?? const <CatalogSong>[];
  final loading = catalog.isLoading || songs.isLoading;
  if (artists.isEmpty && albums.isEmpty && songList.isEmpty && !loading) {
    return const [];
  }

  final cardWidth = AlbumCardMetrics.width(device);
  final spacing = AlbumCardMetrics.crossAxisSpacing(device);
  final gap = SliverToBoxAdapter(
    child: SizedBox(height: device.isMobile ? 12 : 20),
  );

  Widget row(int count, Widget Function(int index) item, double height) =>
      SliverToBoxAdapter(
        child: SizedBox(
          height: height,
          child: HorizontalScrollRegion(
            controlsHeight: cardWidth,
            builder: (context, controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: count,
              separatorBuilder: (context, index) => SizedBox(width: spacing),
              itemBuilder: (context, index) =>
                  SizedBox(width: cardWidth, child: item(index)),
            ),
          ),
        ),
      );

  return [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            const Text('Get from Lidarr', style: TextStyle(fontSize: 20)),
            if (loading) ...[
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
    if (artists.isNotEmpty) ...[
      _subheader('Artists'),
      row(
        artists.length,
        (index) => _ArtistCard(artist: artists[index], width: cardWidth),
        cardWidth + 48,
      ),
      gap,
    ],
    if (albums.isNotEmpty) ...[
      _subheader('Albums'),
      row(
        albums.length,
        (index) => LidarrAlbumCard(album: albums[index], width: cardWidth),
        AlbumCardMetrics.height(cardWidth, isTablet: device.isTablet),
      ),
      gap,
    ],
    if (songList.isNotEmpty) ...[
      _subheader('Songs'),
      SliverList.builder(
        itemCount: songList.length.clamp(0, 8),
        itemBuilder: (context, index) => _SongTile(song: songList[index]),
      ),
      gap,
    ] else if (songs.isLoading)
      const SliverToBoxAdapter(child: TextLinesShimmer(count: 3)),
  ];
}

Widget _subheader(String title) => SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
);

List<ContextMenuAction> lidarrAlbumActions(
  BuildContext context,
  WidgetRef ref,
  CatalogAlbum album,
) {
  Future<void> request(LidarrAction action) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    final resolved = await resolveCatalogAlbum(client, album);
    if (resolved == null) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text("Lidarr doesn't know \"${album.title}\"")),
        );
      }
      return;
    }
    if (context.mounted) {
      await requestFromLidarr(context, ref, resolved, action);
    }
  }

  return [
    ContextMenuAction(
      entry: ContextMenuEntry.selectSongs,
      icon: const Icon(Icons.checklist),
      label: const Text('Choose songs…'),
      run: () => openCatalogAlbum(context, ref, album),
    ),
    ContextMenuAction(
      entry: ContextMenuEntry.requestFromLidarr,
      icon: const Icon(Icons.library_add_outlined),
      label: const Text('Add to library'),
      run: () => request(LidarrAction.library),
    ),
    ContextMenuAction(
      entry: ContextMenuEntry.requestFromLidarr,
      icon: const Icon(JPlayer.download),
      label: const Text('Download'),
      run: () => request(LidarrAction.download),
    ),
    ContextMenuAction(
      entry: ContextMenuEntry.requestFromLidarr,
      icon: const Icon(Icons.playlist_add),
      label: const Text('Add to playlist'),
      run: () => request(LidarrAction.playlist),
    ),
  ];
}

class LidarrAlbumCard extends ConsumerWidget {
  const LidarrAlbumCard({required this.album, required this.width, super.key});

  final CatalogAlbum album;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(
      context,
    ).colorScheme.onPrimary.withValues(alpha: 0.6);
    final stored = album.lidarr;
    final inLibrary =
        stored != null &&
        stored.isInLidarr &&
        stored.trackCount > 0 &&
        stored.trackFileCount >= stored.trackCount;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openCatalogAlbum(context, ref, album),
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
          // The cover gives way so the title row always fits the card.
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    LidarrCoverImage(url: album.coverUrl, size: box.maxWidth),
                    if (inLibrary) const _Badge('In library'),
                  ],
                ),
              ),
            ),
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
                      [
                        album.artistName,
                        if (album.typeLabel.isNotEmpty) album.typeLabel,
                        if (album.year != null) '${album.year}',
                      ].join(' • '),
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

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 6,
    left: 6,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    ),
  );
}

class _ArtistCard extends ConsumerWidget {
  const _ArtistCard({required this.artist, required this.width});

  final LidarrArtist artist;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(
      context,
    ).colorScheme.onPrimary.withValues(alpha: 0.6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showLidarrArtistSheet(context, artist),
      child: Column(
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    LidarrCoverImage(
                      url: artist.imageUrl,
                      size: box.maxWidth,
                      circle: true,
                    ),
                    if (artist.isInLidarr) const _Badge('In Lidarr'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (artist.disambiguation case final note?)
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted),
            ),
        ],
      ),
    );
  }
}

class _SongTile extends ConsumerWidget {
  const _SongTile({required this.song});

  final CatalogSong song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(
      context,
    ).colorScheme.onPrimary.withValues(alpha: 0.6);
    final minutes = song.duration.inMinutes;
    final seconds = song.duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: LidarrCoverImage(url: song.coverUrl, size: 46),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [song.artistName, ?song.albumTitle].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: muted, fontSize: 12),
      ),
      trailing: song.duration > Duration.zero
          ? Text('$minutes:$seconds', style: TextStyle(color: muted))
          : null,
      onTap: () => openCatalogSong(context, ref, song),
    );
  }
}

Future<void> showLidarrArtistSheet(BuildContext context, LidarrArtist artist) =>
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
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            _ArtistSheet(artist: artist, controller: controller),
      ),
    );

class _ArtistSheet extends ConsumerWidget {
  const _ArtistSheet({required this.artist, required this.controller});

  final LidarrArtist artist;
  final ScrollController controller;

  static const _sections = [
    ('Albums', 'album'),
    ('EPs', 'ep'),
    ('Singles', 'single'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(lidarrArtistAlbumsProvider(artist));
    final muted = Theme.of(
      context,
    ).colorScheme.onPrimary.withValues(alpha: 0.6);
    final list = albums.valueOrNull ?? const <CatalogAlbum>[];

    String sectionOf(CatalogAlbum album) {
      if (album.secondaryTypes.isNotEmpty) return 'other';
      final type = album.primaryType?.toLowerCase();
      return _sections.any((s) => s.$2 == type) ? type! : 'other';
    }

    final grouped = <String, List<CatalogAlbum>>{};
    for (final album in list) {
      grouped.putIfAbsent(sectionOf(album), () => []).add(album);
    }

    return SafeArea(
      top: false,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  LidarrCoverImage(
                    url: artist.imageUrl,
                    size: 72,
                    circle: true,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          artist.isInLidarr
                              ? 'In Lidarr. Pick an album to request it.'
                              : 'Pick an album. Only that album is monitored.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (albums.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: TextLinesShimmer(count: 8),
              ),
            )
          else if (albums.hasError || list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  albums.hasError
                      ? "Couldn't load this artist's albums"
                      : 'No albums found',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            for (final (title, key) in [..._sections, ('Other', 'other')])
              if (grouped[key] case final items? when items.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final album = items[index];
                    return ListTile(
                      leading: LidarrCoverImage(url: album.coverUrl, size: 44),
                      title: Text(album.title),
                      subtitle: Text(
                        [
                          if (album.secondaryTypes.isNotEmpty)
                            album.secondaryTypes.join(', '),
                          if (album.year != null) '${album.year}',
                        ].join(' • '),
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openCatalogAlbum(context, ref, album),
                    );
                  },
                ),
              ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
