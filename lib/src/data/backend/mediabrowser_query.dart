import 'package:flutter/foundation.dart';
import 'package:jplayer/src/data/dto/dto.dart';
import 'package:jplayer/src/data/backend/library_query.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:retrofit/retrofit.dart';

String mediaBrowserSort(ItemSort sort, {ItemKind target = ItemKind.album}) =>
    switch (sort) {
      ItemSort.name => 'SortName',
      ItemSort.albumArtist => 'AlbumArtist',
      ItemSort.dateCreated || ItemSort.dateLiked => 'DateCreated,SortName',
      ItemSort.releaseDate => 'PremiereDate,ProductionYear,SortName',
      ItemSort.datePlayed => 'DatePlayed',
      ItemSort.playCount => 'PlayCount',
      ItemSort.dateLastContentAdded => 'DateLastContentAdded',
      ItemSort.albumOrder => 'AlbumArtist,Album,ParentIndexNumber,IndexNumber',
      ItemSort.random => 'Random',
    };

String mediaBrowserSortOrder(SortDirection direction) => switch (direction) {
  SortDirection.ascending => 'Ascending',
  SortDirection.descending => 'Descending',
};

List<String> mediaBrowserFilters(Set<ItemFilterFlag> filters) => [
  for (final flag in filters)
    switch (flag) {
      ItemFilterFlag.favorite => 'IsFavorite',
      ItemFilterFlag.played => 'IsPlayed',
      ItemFilterFlag.unplayed => 'IsUnplayed',
    },
];

List<String> mediaBrowserFields(Set<ItemField> fields) => [
  for (final field in fields)
    switch (field) {
      ItemField.audioSources => 'MediaSources',
      ItemField.genres => 'Genres',
      ItemField.externalIds => 'ProviderIds',
    },
];

/// Logs what an Emby/Jellyfin items query returned, so odd entries (videos
/// in favourites, playlists nobody made) can be traced to the server data.
void logMediaBrowserItems(String label, HttpResponse<ItemsWrapper> response) {
  final data = response.response.data;
  final items = data is Map ? data['Items'] : null;
  if (items is! List) return;
  debugPrint(
    '[Library] $label: ${items.length} of ${data['TotalRecordCount']} '
    '(${response.response.requestOptions.uri.path})',
  );
  for (final item in items.whereType<Map<dynamic, dynamic>>().take(60)) {
    debugPrint(
      '[Library]   ${item['Name']} • type=${item['Type']} '
      'media=${item['MediaType']} collection=${item['CollectionType']} '
      'children=${item['ChildCount']} id=${item['Id']} '
      'path=${item['Path']}',
    );
  }
}

/// Keeps only real, non-video playlists. Emby can return other items
/// (songs, movies) from a playlist query, so the list is checked here
/// rather than trusting the server's type filter.
LibraryPage onlyMusicPlaylists(
  LibraryPage page,
  HttpResponse<ItemsWrapper> response,
) {
  final data = response.response.data;
  final items = data is Map ? data['Items'] : null;
  if (items is! List) return page;
  final keep = <String>{
    for (final item in items.whereType<Map<dynamic, dynamic>>())
      if (item['Type'] == 'Playlist' && item['MediaType'] != 'Video')
        '${item['Id']}',
  };
  final dropped = page.items.length - keep.length;
  if (dropped > 0) {
    debugPrint('[Library] hid $dropped items that are not music playlists');
  }
  return page.copyWith(
    items: [
      for (final item in page.items)
        if (keep.contains(item.id)) item,
    ],
  );
}

/// Remembers which playlists hold any music, so playlists made only of TV
/// episodes or movies can be hidden without asking the server every time.
class MusicPlaylistCheck {
  MusicPlaylistCheck(this._audioCount);

  final Future<int> Function(String playlistId) _audioCount;
  final _hasMusic = <String, bool>{};

  Future<LibraryPage> filter(LibraryPage page) async {
    final unknown = [
      for (final item in page.items)
        if (!_hasMusic.containsKey(item.id)) item.id,
    ];
    await Future.wait([
      for (final id in unknown)
        _audioCount(id)
            .then((count) => _hasMusic[id] = count > 0)
            .catchError((Object _) => _hasMusic[id] = true),
    ]);
    final hidden = [
      for (final item in page.items)
        if (_hasMusic[item.id] == false) item.name,
    ];
    if (hidden.isNotEmpty) {
      debugPrint('[Library] hid playlists with no music: ${hidden.join(', ')}');
    }
    return page.copyWith(
      items: [
        for (final item in page.items)
          if (_hasMusic[item.id] ?? true) item,
      ],
    );
  }
}

/// Keeps only songs from a playlist that also holds videos.
LibraryPage onlyPlaylistSongs(
  LibraryPage page,
  HttpResponse<ItemsWrapper> response,
) {
  final data = response.response.data;
  final items = data is Map ? data['Items'] : null;
  if (items is! List) return page;
  final songs = <String>{
    for (final item in items.whereType<Map<dynamic, dynamic>>())
      if (item['Type'] == 'Audio') '${item['Id']}',
  };
  return page.copyWith(
    items: [
      for (final item in page.items)
        if (songs.contains(item.id)) item,
    ],
  );
}
