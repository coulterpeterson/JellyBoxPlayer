import 'package:jplayer/src/core/enums/enums.dart';

class MediaServerCapabilities {
  const MediaServerCapabilities({
    this.lyrics = true,
    this.similarAlbums = true,
    this.playlistSearch = true,
    this.playlistFavourites = true,
    this.soundSearch = false,
    this.ratings = false,
    this.likedTimestamp = false,
    this.deleteItems = true,
    this.artistScopes = const {ArtistScope.albumArtists},
  });

  final bool lyrics;
  final bool similarAlbums;
  final bool playlistSearch;
  final bool playlistFavourites;
  final bool soundSearch;
  final bool ratings;
  final bool likedTimestamp;
  final bool deleteItems;
  final Set<ArtistScope> artistScopes;

  MediaServerCapabilities copyWith({
    bool? lyrics,
    bool? similarAlbums,
    bool? playlistSearch,
    bool? playlistFavourites,
    bool? soundSearch,
    bool? ratings,
    bool? likedTimestamp,
    bool? deleteItems,
    Set<ArtistScope>? artistScopes,
  }) => MediaServerCapabilities(
    lyrics: lyrics ?? this.lyrics,
    similarAlbums: similarAlbums ?? this.similarAlbums,
    playlistSearch: playlistSearch ?? this.playlistSearch,
    playlistFavourites: playlistFavourites ?? this.playlistFavourites,
    soundSearch: soundSearch ?? this.soundSearch,
    ratings: ratings ?? this.ratings,
    likedTimestamp: likedTimestamp ?? this.likedTimestamp,
    deleteItems: deleteItems ?? this.deleteItems,
    artistScopes: artistScopes ?? this.artistScopes,
  );
}
