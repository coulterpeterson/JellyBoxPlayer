import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jplayer/src/data/backend/mediabrowser_query.dart';
import 'package:jplayer/src/data/dto/dto.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:retrofit/retrofit.dart';

void main() {
  test('onlyMusicPlaylists drops songs, movies and video playlists', () {
    final raw = {
      'Items': [
        {
          'Id': 'p1',
          'Name': 'Road trip',
          'Type': 'Playlist',
          'MediaType': 'Audio',
        },
        {'Id': 'p2', 'Name': 'Mixed', 'Type': 'Playlist'},
        {
          'Id': 'p3',
          'Name': 'Movie night',
          'Type': 'Playlist',
          'MediaType': 'Video',
        },
        {'Id': 's1', 'Name': 'Maps', 'Type': 'Audio', 'MediaType': 'Audio'},
        {
          'Id': 'm1',
          'Name': 'The Big Short',
          'Type': 'Movie',
          'MediaType': 'Video',
        },
      ],
      'TotalRecordCount': 5,
    };
    final response = HttpResponse(
      const ItemsWrapper(items: []),
      Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(),
        data: raw,
      ),
    );
    final page = LibraryPage(
      items: [
        for (final item in raw['Items']! as List<Map<String, String>>)
          LibraryItem(
            id: item['Id']!,
            name: item['Name']!,
            kind: ItemKind.playlist,
          ),
      ],
    );

    final filtered = onlyMusicPlaylists(page, response);

    expect([for (final item in filtered.items) item.id], ['p1', 'p2']);
  });
}
