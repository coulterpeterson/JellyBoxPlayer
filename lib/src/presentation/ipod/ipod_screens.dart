import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:jplayer/resources/resources.dart';
import 'package:jplayer/src/core/enums/enums.dart';
import 'package:jplayer/src/data/backend/library_query.dart';
import 'package:jplayer/src/data/providers/providers.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/player_bar_provider.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/ipod/ipod_games.dart';
import 'package:jplayer/src/presentation/ipod/ipod_shell.dart';
import 'package:jplayer/src/presentation/widgets/marquee_text.dart';
import 'package:jplayer/src/providers/image_service_provider.dart';

class IpodMenuItem {
  const IpodMenuItem(
    this.label, {
    required this.onSelect,
    this.detail,
    this.chevron = true,
  });

  final String label;
  final String? detail;
  final bool chevron;
  final void Function(BuildContext context) onSelect;
}

IpodPage mainMenuPage() => IpodPage(
  title: 'iPod',
  showArt: true,
  builder: (key) => IpodMenu(key: key, items: _mainMenuItems),
);

List<IpodMenuItem> _mainMenuItems(BuildContext context, WidgetRef ref) {
  final nav = IpodNavigator.of(context);
  return [
    IpodMenuItem(
      'Music',
      onSelect: (_) => nav.push(
        IpodPage(
          title: 'Music',
          builder: (key) => IpodMenu(key: key, items: _musicMenuItems),
        ),
      ),
    ),
    IpodMenuItem(
      'Shuffle Songs',
      chevron: false,
      onSelect: (context) => unawaited(_shuffleSongs(context, ref)),
    ),
    IpodMenuItem(
      'Games',
      onSelect: (_) => nav.push(
        IpodPage(
          title: 'Games',
          builder: (key) => IpodMenu(key: key, items: _gamesMenuItems),
        ),
      ),
    ),
    IpodMenuItem(
      'Settings',
      onSelect: (_) => nav.push(
        IpodPage(
          title: 'Settings',
          builder: (key) => IpodMenu(key: key, items: _settingsMenuItems),
        ),
      ),
    ),
    if (ref.watch(barSongProvider) != null)
      IpodMenuItem('Now Playing', onSelect: (_) => nav.openNowPlaying()),
  ];
}

String? _libraryId(WidgetRef ref) =>
    ref.read(currentLibraryProvider).valueOrNull?.id;

List<IpodMenuItem> _musicMenuItems(BuildContext context, WidgetRef ref) {
  final nav = IpodNavigator.of(context);
  final client = ref.read(mediaServerClientProvider);
  IpodMenuItem list(String label, IpodLoader load, IpodItemSelected select) =>
      IpodMenuItem(
        label,
        onSelect: (_) => nav.push(
          IpodPage(
            title: label,
            builder: (key) =>
                IpodItemList(key: key, load: load, onSelected: select),
          ),
        ),
      );

  return [
    list(
      'Playlists',
      (start) =>
          client.getPlaylists(LibraryQuery(startIndex: start, limit: 200)),
      (context, item, _) => _openSongs(
        context,
        item,
        () async => (await client.getPlaylistSongs(item.id)).items,
      ),
    ),
    list(
      'Artists',
      (start) => client.getArtists(
        LibraryQuery(
          libraryId: _libraryId(ref),
          startIndex: start,
          limit: 200,
          artistScope: ArtistScope.albumArtists,
        ),
      ),
      (context, artist, _) => _openArtist(context, ref, artist),
    ),
    list(
      'Albums',
      (start) => client.getAlbums(
        LibraryQuery(libraryId: _libraryId(ref), startIndex: start, limit: 200),
      ),
      (context, album, _) => _openAlbum(context, ref, album),
    ),
    list(
      'Songs',
      (start) => client.getAllSongs(
        LibraryQuery(libraryId: _libraryId(ref), startIndex: start, limit: 200),
      ),
      (context, song, songs) => _play(context, ref, song, songs),
    ),
    list(
      'Genres',
      (start) => client.getGenres(
        LibraryQuery(libraryId: _libraryId(ref), startIndex: start, limit: 200),
      ),
      (context, genre, _) => IpodNavigator.of(context).push(
        IpodPage(
          title: genre.name,
          builder: (key) => IpodItemList(
            key: key,
            load: (start) => client.getAlbums(
              LibraryQuery(
                libraryId: _libraryId(ref),
                genreIds: [genre.id],
                startIndex: start,
                limit: 200,
              ),
            ),
            onSelected: (context, album, _) => _openAlbum(context, ref, album),
          ),
        ),
      ),
    ),
  ];
}

void _openArtist(BuildContext context, WidgetRef ref, LibraryItem artist) {
  final client = ref.read(mediaServerClientProvider);
  IpodNavigator.of(context).push(
    IpodPage(
      title: artist.name,
      builder: (key) => IpodItemList(
        key: key,
        load: (start) => client.getAlbums(
          LibraryQuery(
            libraryId: _libraryId(ref),
            artistIds: [artist.id],
            sort: ItemSort.releaseDate,
            startIndex: start,
            limit: 200,
          ),
        ),
        onSelected: (context, album, _) => _openAlbum(context, ref, album),
      ),
    ),
  );
}

void _openAlbum(BuildContext context, WidgetRef ref, LibraryItem album) {
  final client = ref.read(mediaServerClientProvider);
  _openSongs(context, album, () async {
    final songs = [...(await client.getSongs(album.id)).items]
      ..sort(LibraryItem.compareAlbumOrder);
    return songs;
  });
}

void _openSongs(
  BuildContext context,
  LibraryItem set,
  Future<List<LibraryItem>> Function() load,
) {
  IpodNavigator.of(context).push(
    IpodPage(
      title: set.name,
      builder: (key) => IpodItemList(
        key: key,
        load: (start) async =>
            start > 0 ? const LibraryPage() : LibraryPage(items: await load()),
        chevrons: false,
        onSelected: (context, song, songs) =>
            _play(context, null, song, songs, set: set),
      ),
    ),
  );
}

Future<void> _play(
  BuildContext context,
  WidgetRef? ref,
  LibraryItem song,
  List<LibraryItem> songs, {
  LibraryItem? set,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final nav = IpodNavigator.of(context);
  final source =
      set ??
      LibraryItem(
        id: song.albumId ?? song.id,
        name: song.albumName ?? '',
        kind: ItemKind.album,
        albumArtist: song.albumArtist,
        images: song.images,
      );
  nav.openNowPlaying();
  await container
      .read(playbackProvider.notifier)
      .play(song, songs, source, sourceId: set?.id);
}

Future<void> _shuffleSongs(BuildContext context, WidgetRef ref) async {
  final page = await ref
      .read(mediaServerClientProvider)
      .getAllSongs(
        LibraryQuery(
          libraryId: _libraryId(ref),
          sort: ItemSort.random,
          limit: 200,
        ),
      );
  if (page.items.isEmpty || !context.mounted) return;
  await _play(
    context,
    ref,
    page.items.first,
    page.items,
    set: const LibraryItem(
      id: 'ipod-shuffle',
      name: 'Shuffle Songs',
      kind: ItemKind.playlist,
    ),
  );
}

List<IpodMenuItem> _gamesMenuItems(BuildContext context, WidgetRef ref) {
  final nav = IpodNavigator.of(context);
  IpodMenuItem game(String name, Widget Function(GlobalKey key) build) =>
      IpodMenuItem(
        name,
        chevron: false,
        onSelect: (_) => nav.push(IpodPage(title: name, builder: build)),
      );
  return [
    game('Brick', (key) => BreakoutGame(key: key)),
    game('Pong', (key) => PongGame(key: key)),
    game('Snake', (key) => SnakeGame(key: key)),
  ];
}

List<IpodMenuItem> _settingsMenuItems(BuildContext context, WidgetRef ref) {
  final settings = ref.read(appSettingsProvider.notifier);
  final haptics = ref.watch(settingProvider(AppSetting.ipodHaptics));
  final black = ref.watch(settingProvider(AppSetting.ipodBlack));
  final shuffle = ref.watch(barShuffleProvider);
  return [
    IpodMenuItem(
      'Shuffle',
      detail: shuffle ? 'Songs' : 'Off',
      chevron: false,
      onSelect: (_) => ref
          .read(playbackProvider.notifier)
          .setShuffle(enabled: !shuffle)
          .ignore(),
    ),
    IpodMenuItem(
      'Clicker',
      detail: haptics ? 'On' : 'Off',
      chevron: false,
      onSelect: (_) =>
          settings.setEnabled(AppSetting.ipodHaptics, value: !haptics),
    ),
    IpodMenuItem(
      'Colour',
      detail: black ? 'Black' : 'Silver',
      chevron: false,
      onSelect: (_) => settings.setEnabled(AppSetting.ipodBlack, value: !black),
    ),
    IpodMenuItem(
      'Exit iPod Mode',
      chevron: false,
      onSelect: (_) => settings.setEnabled(AppSetting.ipodMode, value: false),
    ),
  ];
}

/// Rows the size of the classic iPod's, scaled to the display.
double ipodRowHeight(double displayHeight) => math.max(22, displayHeight / 9.6);

class IpodRows extends StatelessWidget {
  const IpodRows({
    required this.labels,
    required this.selected,
    required this.top,
    this.details,
    this.chevrons,
    super.key,
  });

  final List<String> labels;
  final List<String?>? details;
  final List<bool>? chevrons;
  final int selected;
  final int top;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rowHeight = ipodRowHeight(constraints.maxHeight + 24);
      final visible = (constraints.maxHeight / rowHeight).floor();
      final overflow = labels.length > visible;
      final fontSize = rowHeight * 0.58;
      return Stack(
        children: [
          Column(
            children: [
              for (var i = top; i < math.min(labels.length, top + visible); i++)
                _row(
                  label: labels[i],
                  detail: details?[i],
                  chevron: chevrons?[i] ?? true,
                  highlighted: i == selected,
                  height: rowHeight,
                  fontSize: fontSize,
                  rightInset: overflow ? 9 : 0,
                ),
            ],
          ),
          if (overflow)
            Positioned(
              right: 1,
              top: 1,
              bottom: 1,
              width: 7,
              child: _Scrollbar(
                fraction: visible / labels.length,
                position: top / math.max(1, labels.length - visible),
              ),
            ),
        ],
      );
    },
  );

  Widget _row({
    required String label,
    required String? detail,
    required bool chevron,
    required bool highlighted,
    required double height,
    required double fontSize,
    required double rightInset,
  }) {
    final color = highlighted ? Colors.white : Colors.black;
    return Container(
      height: height,
      margin: EdgeInsets.only(right: rightInset),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: highlighted
          ? const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6CADF2), Color(0xFF2F74D0)],
              ),
              border: Border(
                top: BorderSide(color: Color(0xFF3F7FD5)),
                bottom: BorderSide(color: Color(0xFF1E5CB3)),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ipodTextStyle.copyWith(color: color, fontSize: fontSize),
            ),
          ),
          if (detail != null)
            Text(
              detail,
              style: ipodTextStyle.copyWith(
                color: highlighted ? Colors.white : const Color(0xFF555555),
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
              ),
            ),
          if (chevron)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right,
                size: fontSize * 1.3,
                color: highlighted ? Colors.white : const Color(0xFF8A8A8A),
              ),
            ),
        ],
      ),
    );
  }
}

class _Scrollbar extends StatelessWidget {
  const _Scrollbar({required this.fraction, required this.position});

  final double fraction;
  final double position;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      final thumb = math.max(12, height * fraction).toDouble();
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF8E9094), width: 0.8),
          color: const Color(0xFFEDEDED),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: (height - thumb) * position.clamp(0.0, 1.0),
              height: thumb,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6CADF2), Color(0xFF2F74D0)],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

mixin _ScrollingRows<T extends ConsumerStatefulWidget> on IpodScreenState<T> {
  var selected = 0;
  var top = 0;
  int visibleRows = 7;

  int get length;

  @override
  void onScroll(int step) {
    if (length == 0) return;
    final next = (selected + step).clamp(0, length - 1);
    if (next == selected) return;
    setState(() {
      selected = next;
      if (selected < top) top = selected;
      if (selected >= top + visibleRows) top = selected - visibleRows + 1;
    });
    onSelectionChanged();
  }

  void onSelectionChanged() {}

  Widget rows({
    required List<String> labels,
    List<String?>? details,
    List<bool>? chevrons,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      visibleRows = math.max(
        1,
        (constraints.maxHeight / ipodRowHeight(constraints.maxHeight + 24))
            .floor(),
      );
      return IpodRows(
        labels: labels,
        details: details,
        chevrons: chevrons,
        selected: selected,
        top: top,
      );
    },
  );
}

/// A static menu, like the main menu or Settings.
class IpodMenu extends ConsumerStatefulWidget {
  const IpodMenu({required this.items, super.key});

  final List<IpodMenuItem> Function(BuildContext context, WidgetRef ref) items;

  @override
  ConsumerState<IpodMenu> createState() => _IpodMenuState();
}

class _IpodMenuState extends IpodScreenState<IpodMenu>
    with _ScrollingRows<IpodMenu> {
  List<IpodMenuItem> _items = const [];

  @override
  int get length => _items.length;

  @override
  void onSelect() {
    if (selected >= _items.length) return;
    _items[selected].onSelect(context);
  }

  @override
  Widget build(BuildContext context) {
    _items = widget.items(context, ref);
    if (selected >= _items.length) selected = math.max(0, _items.length - 1);
    return rows(
      labels: [for (final item in _items) item.label],
      details: [for (final item in _items) item.detail],
      chevrons: [for (final item in _items) item.chevron],
    );
  }
}

typedef IpodLoader = Future<LibraryPage> Function(int start);
typedef IpodItemSelected =
    void Function(
      BuildContext context,
      LibraryItem item,
      List<LibraryItem> all,
    );

/// A list of library items loaded page by page from the server.
class IpodItemList extends ConsumerStatefulWidget {
  const IpodItemList({
    required this.load,
    required this.onSelected,
    this.chevrons = true,
    super.key,
  });

  final IpodLoader load;
  final IpodItemSelected onSelected;
  final bool chevrons;

  @override
  ConsumerState<IpodItemList> createState() => _IpodItemListState();
}

class _IpodItemListState extends IpodScreenState<IpodItemList>
    with _ScrollingRows<IpodItemList> {
  final _items = <LibraryItem>[];
  var _total = 0;
  var _loading = true;
  var _failed = false;

  @override
  int get length => _items.length;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    try {
      final page = await widget.load(_items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = math.max(page.totalRecordCount, _items.length);
        if (page.items.isEmpty) _total = _items.length;
        _loading = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void onSelectionChanged() {
    if (!_loading && _items.length < _total && selected > _items.length - 30) {
      _loading = true;
      unawaited(_loadMore());
    }
  }

  @override
  void onSelect() {
    if (selected >= _items.length) return;
    widget.onSelected(context, _items[selected], List.of(_items));
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Center(
        child: _loading
            ? const _IpodSpinner()
            : Text(
                _failed ? "Couldn't load" : 'Nothing here',
                style: ipodTextStyle.copyWith(color: const Color(0xFF666666)),
              ),
      );
    }
    return rows(
      labels: [
        for (final item in _items) item.name,
      ],
      chevrons: [for (final _ in _items) widget.chevrons],
    );
  }
}

class _IpodSpinner extends StatelessWidget {
  const _IpodSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 26,
    child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF7A7A7A)),
  );
}

/// The right half of the main menu: cover art slowly drifting across.
class IpodArtPanel extends ConsumerStatefulWidget {
  const IpodArtPanel({super.key});

  @override
  ConsumerState<IpodArtPanel> createState() => _IpodArtPanelState();
}

class _IpodArtPanelState extends ConsumerState<IpodArtPanel> {
  List<LibraryItem> _albums = const [];
  var _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAlbums());
    _timer = Timer.periodic(const Duration(seconds: 16), (_) {
      if (_albums.length > 1 && mounted) {
        setState(() => _index = (_index + 1) % _albums.length);
      }
    });
  }

  Future<void> _loadAlbums() async {
    try {
      final albums = await ref
          .read(mediaServerClientProvider)
          .getLatestAlbums(libraryId: _libraryId(ref), limit: 12);
      if (mounted) setState(() => _albums = [...albums]..shuffle());
    } on Object {
      // Leave the panel showing the current song or the placeholder.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(barSongProvider);
    final item = song ?? (_albums.isEmpty ? null : _albums[_index]);
    return _PanningArt(
      image: item == null
          ? const AssetImage(Images.album)
          : ref.read(imageServiceProvider).itemImage(item),
    );
  }
}

class _PanningArt extends StatefulWidget {
  const _PanningArt({required this.image});

  final ImageProvider image;

  @override
  State<_PanningArt> createState() => _PanningArtState();
}

class _PanningArtState extends State<_PanningArt>
    with SingleTickerProviderStateMixin {
  late final _pan = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = constraints.maxHeight;
      return ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 900),
          child: AnimatedBuilder(
            key: ValueKey(widget.image),
            animation: _pan,
            builder: (context, child) => OverflowBox(
              minWidth: side,
              maxWidth: side,
              minHeight: side,
              maxHeight: side,
              alignment: Alignment(
                Curves.easeInOut.transform(_pan.value) * 2 - 1,
                0,
              ),
              child: child,
            ),
            child: Image(
              image: widget.image,
              width: side,
              height: side,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Image.asset(
                Images.album,
                width: side,
                height: side,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    },
  );
}

IpodPage nowPlayingPage() => IpodPage(
  title: 'Now Playing',
  builder: (key) => NowPlayingScreen(key: key),
);

enum _WheelMode { volume, scrub }

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends IpodScreenState<NowPlayingScreen> {
  var _mode = _WheelMode.volume;
  double? _volume;
  Duration? _scrubTo;
  Timer? _hideVolume;
  Timer? _commitScrub;
  var _showVolume = false;

  @override
  void initState() {
    super.initState();
    FlutterVolumeController.updateShowSystemUI(false).ignore();
    unawaited(_readVolume());
  }

  Future<void> _readVolume() async {
    try {
      final volume = await FlutterVolumeController.getVolume();
      if (mounted) _volume = volume;
    } on Object {
      _volume = ref.read(volumeProvider).level;
    }
  }

  @override
  void dispose() {
    FlutterVolumeController.updateShowSystemUI(true).ignore();
    _hideVolume?.cancel();
    _commitScrub?.cancel();
    super.dispose();
  }

  @override
  void onScroll(int step) {
    switch (_mode) {
      case _WheelMode.volume:
        final next = ((_volume ?? 0.5) + step * 0.03).clamp(0.0, 1.0);
        setState(() {
          _volume = next;
          _showVolume = true;
        });
        FlutterVolumeController.setVolume(next).ignore();
        _hideVolume?.cancel();
        _hideVolume = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _showVolume = false);
        });
      case _WheelMode.scrub:
        final progress = ref.read(barProgressProvider);
        final current = _scrubTo ?? progress.position;
        final next = current + Duration(seconds: step * 3);
        setState(
          () => _scrubTo = Duration(
            milliseconds: next.inMilliseconds.clamp(
              0,
              progress.duration.inMilliseconds,
            ),
          ),
        );
        _commitScrub?.cancel();
        _commitScrub = Timer(const Duration(milliseconds: 500), _seek);
    }
  }

  void _seek() {
    final target = _scrubTo;
    if (target == null) return;
    ref.read(barControlsProvider).seek(target).ignore();
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _scrubTo = null);
    });
  }

  @override
  void onSelect() => setState(() {
    _mode = _mode == _WheelMode.volume ? _WheelMode.scrub : _WheelMode.volume;
    _showVolume = false;
  });

  @override
  bool onMenu() {
    if (_mode == _WheelMode.scrub) {
      setState(() => _mode = _WheelMode.volume);
      return true;
    }
    return false;
  }

  static String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(barSongProvider);
    if (song == null) {
      return Center(
        child: Text(
          'Nothing playing',
          style: ipodTextStyle.copyWith(color: const Color(0xFF666666)),
        ),
      );
    }
    final progress = ref.watch(barProgressProvider);
    final queue = ref.watch(barQueueProvider);
    final index = ref.watch(barQueueIndexProvider);
    final image = ref.read(imageServiceProvider).itemImage(song);
    final position = _scrubTo ?? progress.position;
    final duration = progress.duration;
    final remaining = duration - position;

    return LayoutBuilder(
      builder: (context, constraints) {
        final art = constraints.maxHeight * 0.52;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFE7E7E9)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    if (index != null && queue.isNotEmpty)
                      Text(
                        '${index + 1} of ${queue.length}',
                        style: ipodTextStyle.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    const Spacer(),
                    const Icon(
                      Icons.format_list_bulleted,
                      size: 16,
                      color: Color(0xFF9AA3B5),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    children: [
                      _Reflected(image: image, size: art),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 24,
                              child: MarqueeText(
                                song.name,
                                style: ipodTextStyle.copyWith(fontSize: 17),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artistLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ipodTextStyle.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF6B6B6B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.albumName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ipodTextStyle.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF6B6B6B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showVolume)
                  _VolumeBar(value: _volume ?? 0)
                else
                  _ProgressBar(
                    elapsed: _time(position),
                    remaining:
                        '-${_time(remaining.isNegative ? Duration.zero : remaining)}',
                    fraction: duration.inMilliseconds == 0
                        ? 0
                        : position.inMilliseconds / duration.inMilliseconds,
                    scrubbing: _mode == _WheelMode.scrub,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Reflected extends StatelessWidget {
  const _Reflected({required this.image, required this.size});

  final ImageProvider image;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget art() => Image(
      image: image,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.asset(
        Images.album,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        art(),
        SizedBox(
          height: size * 0.22,
          width: size,
          child: ClipRect(
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: size,
                child: Transform.flip(flipY: true, child: art()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.elapsed,
    required this.remaining,
    required this.fraction,
    required this.scrubbing,
  });

  final String elapsed;
  final String remaining;
  final double fraction;
  final bool scrubbing;

  @override
  Widget build(BuildContext context) {
    final label = ipodTextStyle.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          SizedBox(width: 38, child: Text(elapsed, style: label)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final filled = width * fraction.clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 9,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFBFC2C7)),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFF8F8F8), Color(0xFFDADCE0)],
                        ),
                      ),
                    ),
                    Container(
                      height: 9,
                      width: filled,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF7DB9F5), Color(0xFF2C73D2)],
                        ),
                      ),
                    ),
                    if (scrubbing)
                      Positioned(
                        left: filled - 6,
                        child: Transform.rotate(
                          angle: math.pi / 4,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFF2C73D2),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(remaining, style: label, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: Row(
      children: [
        const Icon(Icons.volume_mute, size: 16, color: Color(0xFF555555)),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 9,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFBFC2C7)),
              color: const Color(0xFFEDEDED),
            ),
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF7DB9F5), Color(0xFF2C73D2)],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.volume_up, size: 16, color: Color(0xFF555555)),
      ],
    ),
  );
}
