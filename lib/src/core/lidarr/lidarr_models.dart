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
