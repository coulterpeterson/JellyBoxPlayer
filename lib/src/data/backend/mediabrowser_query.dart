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
