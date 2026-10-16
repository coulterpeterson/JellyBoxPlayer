/// Lightweight views over Lidarr's v1 API resources. The raw JSON is kept
/// so it can be sent back unchanged when adding an album.
class LidarrAlbum {
  const LidarrAlbum(this.json);

  final Map<String, dynamic> json;

  int get id => (json['id'] as num?)?.toInt() ?? 0;

  /// Whether Lidarr already tracks this album (lookups return id 0 otherwise).
  bool get isInLidarr => id > 0;

  String get title => json['title'] as String? ?? '';

  String get foreignAlbumId => json['foreignAlbumId'] as String? ?? '';

  bool get monitored => json['monitored'] as bool? ?? false;

  String? get albumType => json['albumType'] as String?;

  DateTime? get releaseDate =>
      DateTime.tryParse(json['releaseDate'] as String? ?? '');

  Map<String, dynamic> get artist =>
      (json['artist'] as Map?)?.cast<String, dynamic>() ?? const {};

  String get artistName =>
      artist['artistName'] as String? ?? json['artistName'] as String? ?? '';

  int get trackCount =>
      (statistics['trackCount'] as num?)?.toInt() ??
      _releases
          .map((release) => (release['trackCount'] as num?)?.toInt() ?? 0)
          .fold(0, (a, b) => a > b ? a : b);

  int get trackFileCount =>
      (statistics['trackFileCount'] as num?)?.toInt() ?? 0;

  Map<String, dynamic> get statistics =>
      (json['statistics'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> get _releases => [
    for (final release in json['releases'] as List? ?? const [])
      if (release is Map) release.cast<String, dynamic>(),
  ];

  /// The album's editions as (id, monitored), the monitored one first.
  List<({int id, bool monitored})> get releases => [
    for (final release in _releases)
      if ((release['id'] as num?)?.toInt() case final int id when id > 0)
        (id: id, monitored: release['monitored'] as bool? ?? false),
  ]..sort((a, b) => (b.monitored ? 1 : 0) - (a.monitored ? 1 : 0));

  @override
  bool operator ==(Object other) =>
      other is LidarrAlbum &&
      other.id == id &&
      other.foreignAlbumId == foreignAlbumId;

  @override
  int get hashCode => Object.hash(id, foreignAlbumId);

  String? get coverUrl {
    final remote = json['remoteCover'] as String?;
    if (remote != null && remote.isNotEmpty) return remote;
    for (final image in json['images'] as List? ?? const []) {
      if (image is! Map) continue;
      if (image['coverType'] != 'cover') continue;
      final url = (image['remoteUrl'] ?? image['url']) as String?;
      if (url != null && url.startsWith('http')) return url;
    }
    return null;
  }
}

class LidarrTrack {
  const LidarrTrack({
    required this.title,
    required this.number,
    this.id = 0,
    this.discNumber = 1,
    this.recordingId,
    this.trackFileId = 0,
    this.hasFile = false,
    this.duration = Duration.zero,
  });

  factory LidarrTrack.fromJson(Map<String, dynamic> json) => LidarrTrack(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    number: (json['absoluteTrackNumber'] as num?)?.toInt() ?? 0,
    discNumber: (json['mediumNumber'] as num?)?.toInt() ?? 1,
    recordingId: json['foreignRecordingId'] as String?,
    trackFileId: (json['trackFileId'] as num?)?.toInt() ?? 0,
    hasFile: json['hasFile'] as bool? ?? false,
    duration: Duration(milliseconds: (json['duration'] as num?)?.toInt() ?? 0),
  );

  final int id;
  final String title;
  final int number;
  final int discNumber;
  final String? recordingId;
  final int trackFileId;
  final bool hasFile;
  final Duration duration;
}

class LidarrQueueItem {
  const LidarrQueueItem(this.json);

  final Map<String, dynamic> json;

  int get albumId => (json['albumId'] as num?)?.toInt() ?? 0;

  double get size => (json['size'] as num?)?.toDouble() ?? 0;

  double get sizeLeft => (json['sizeleft'] as num?)?.toDouble() ?? 0;

  String get status => json['status'] as String? ?? '';

  String get trackedDownloadState =>
      json['trackedDownloadState'] as String? ?? '';

  double? get progress => size > 0 ? (1 - sizeLeft / size).clamp(0, 1) : null;
}

/// Normalises a track or album title so names from Lidarr, MusicBrainz and
/// the media server can be compared.
String normalizeTitle(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
    .replaceAll('&', 'and')
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim();

class LidarrArtist {
  const LidarrArtist(this.json);

  final Map<String, dynamic> json;

  int get id => (json['id'] as num?)?.toInt() ?? 0;

  bool get isInLidarr => id > 0;

  String get name => json['artistName'] as String? ?? '';

  String get foreignArtistId => json['foreignArtistId'] as String? ?? '';

  String? get disambiguation {
    final value = json['disambiguation'] as String?;
    return value == null || value.isEmpty ? null : value;
  }

  String? get imageUrl {
    String? find(String type) {
      for (final image in json['images'] as List? ?? const []) {
        if (image is! Map || image['coverType'] != type) continue;
        final url = (image['remoteUrl'] ?? image['url']) as String?;
        if (url != null && url.startsWith('http')) return url;
      }
      return null;
    }

    final remote = json['remotePoster'] as String?;
    if (remote != null && remote.isNotEmpty) return remote;
    return find('poster') ?? find('fanart') ?? find('banner');
  }

  @override
  bool operator ==(Object other) =>
      other is LidarrArtist && other.foreignArtistId == foreignArtistId;

  @override
  int get hashCode => foreignArtistId.hashCode;
}

/// An album found by searching, from Lidarr or MusicBrainz. MusicBrainz
/// results are turned into a [LidarrAlbum] (looked up by release group id)
/// when the user opens one.
class CatalogAlbum {
  const CatalogAlbum({
    required this.releaseGroupId,
    required this.title,
    required this.artistName,
    this.primaryType,
    this.secondaryTypes = const [],
    this.year,
    this.coverUrl,
    this.lidarr,
  });

  factory CatalogAlbum.fromLidarr(LidarrAlbum album) => CatalogAlbum(
    releaseGroupId: album.foreignAlbumId,
    title: album.title,
    artistName: album.artistName,
    primaryType: album.albumType,
    year: album.releaseDate?.year,
    coverUrl: album.coverUrl,
    lidarr: album,
  );

  final String releaseGroupId;
  final String title;
  final String artistName;
  final String? primaryType;
  final List<String> secondaryTypes;
  final int? year;
  final String? coverUrl;

  /// Set when the result came from Lidarr itself.
  final LidarrAlbum? lidarr;

  String get typeLabel => [
    ?primaryType,
    ...secondaryTypes,
  ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is CatalogAlbum && other.releaseGroupId == releaseGroupId;

  @override
  int get hashCode => releaseGroupId.hashCode;
}

/// A song found by searching, with what's needed to find albums that
/// contain it.
class CatalogSong {
  const CatalogSong({
    required this.title,
    required this.artistName,
    this.albumTitle,
    this.coverUrl,
    this.duration = Duration.zero,
    this.isrc,
    this.deezerId,
    this.recordingId,
    this.releaseGroups = const [],
  });

  final String title;
  final String artistName;
  final String? albumTitle;
  final String? coverUrl;
  final Duration duration;
  final String? isrc;
  final int? deezerId;
  final String? recordingId;

  /// Albums known to contain the song (from a MusicBrainz search).
  final List<CatalogAlbum> releaseGroups;

  @override
  bool operator ==(Object other) =>
      other is CatalogSong &&
      other.title == title &&
      other.artistName == artistName &&
      other.albumTitle == albumTitle &&
      other.recordingId == recordingId;

  @override
  int get hashCode => Object.hash(title, artistName, albumTitle, recordingId);
}

/// Where a picked song can come from: candidate albums, best first, and
/// the MusicBrainz recording ids that identify it.
class SongSource {
  const SongSource({required this.albums, required this.recordingIds});

  final List<CatalogAlbum> albums;
  final Set<String> recordingIds;
}

/// Orders albums containing a song the way a person would pick one: the
/// studio album first, then an EP, then a single; official releases; then
/// the earliest. Live releases and compilations sink to the bottom.
int compareSongAlbums(CatalogAlbum a, CatalogAlbum b, {String? preferTitle}) {
  int rank(CatalogAlbum album) {
    final secondary = album.secondaryTypes.map((t) => t.toLowerCase());
    if (secondary.any((t) => t == 'live' || t == 'compilation')) return 5;
    if (secondary.isNotEmpty) return 4;
    return switch (album.primaryType?.toLowerCase()) {
      'album' => 0,
      'ep' => 1,
      'single' => 2,
      _ => 3,
    };
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  if (preferTitle != null) {
    final wanted = normalizeTitle(preferTitle);
    final aMatch = normalizeTitle(a.title) == wanted ? 0 : 1;
    final bMatch = normalizeTitle(b.title) == wanted ? 0 : 1;
    if (aMatch != bMatch) return aMatch.compareTo(bMatch);
  }
  return (a.year ?? 9999).compareTo(b.year ?? 9999);
}
