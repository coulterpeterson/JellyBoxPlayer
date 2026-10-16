import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/lidarr/lidarr_client.dart';
import 'package:jplayer/src/core/lidarr/lidarr_models.dart';
import 'package:jplayer/src/data/backend/library_query.dart';
import 'package:jplayer/src/data/backend/media_server_client.dart';
import 'package:jplayer/src/data/providers/providers.dart';
import 'package:jplayer/src/domain/models/models.dart';
import 'package:jplayer/src/domain/providers/download_manager_provider.dart';
import 'package:jplayer/src/domain/providers/download_sync_provider.dart';
import 'package:jplayer/src/domain/providers/lidarr_account_provider.dart';

/// What should happen once Lidarr has fetched an album.
enum LidarrAction {
  /// Only add it to the server library.
  library,

  /// Add it to the library, then download it to this device.
  download,

  /// Add it to the library, then add it to a playlist.
  playlist,
}

enum LidarrStage {
  /// Lidarr is looking for a release to grab.
  searching,

  /// Lidarr's download client is fetching the release.
  downloading,

  /// Waiting for the media server to scan the new files in.
  waitingForServer,

  /// Downloading the songs from the media server to this device.
  downloadingToDevice,
  done,
  failed,
}

class WantedTrack {
  const WantedTrack({required this.title, this.recordingId});

  factory WantedTrack.fromJson(Map<String, dynamic> json) => WantedTrack(
    title: json['title'] as String,
    recordingId: json['recordingId'] as String?,
  );

  final String title;
  final String? recordingId;

  Map<String, dynamic> toJson() => {
    'title': title,
    'recordingId': recordingId,
  };

  bool matchesTrack(LidarrTrack track) =>
      (recordingId != null && recordingId == track.recordingId) ||
      normalizeTitle(title) == normalizeTitle(track.title);

  bool matchesSong(LibraryItem song) {
    final ids = song.externalIds;
    if (recordingId != null &&
        (ids[ExternalIdProvider.musicBrainzRecording] == recordingId ||
            ids[ExternalIdProvider.musicBrainzTrack] == recordingId)) {
      return true;
    }
    return normalizeTitle(title) == normalizeTitle(song.name);
  }
}

@immutable
class LidarrRequest {
  const LidarrRequest({
    required this.id,
    required this.lidarrAlbumId,
    required this.foreignAlbumId,
    required this.albumTitle,
    required this.artistName,
    required this.action,
    required this.createdAt,
    this.coverUrl,
    this.playlistId,
    this.playlistName,
    this.wanted,
    this.keepExistingFiles = false,
    this.stage = LidarrStage.searching,
    this.progress,
    this.message,
    this.trimmed = false,
    this.serverAlbumId,
  });

  factory LidarrRequest.fromJson(Map<String, dynamic> json) => LidarrRequest(
    id: json['id'] as String,
    lidarrAlbumId: json['lidarrAlbumId'] as int,
    foreignAlbumId: json['foreignAlbumId'] as String? ?? '',
    albumTitle: json['albumTitle'] as String? ?? '',
    artistName: json['artistName'] as String? ?? '',
    action: LidarrAction.values.byName(json['action'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    coverUrl: json['coverUrl'] as String?,
    playlistId: json['playlistId'] as String?,
    playlistName: json['playlistName'] as String?,
    wanted: (json['wanted'] as List?)
        ?.map((e) => WantedTrack.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    keepExistingFiles: json['keepExistingFiles'] as bool? ?? false,
    stage: LidarrStage.values.byName(json['stage'] as String),
    message: json['message'] as String?,
    trimmed: json['trimmed'] as bool? ?? false,
    serverAlbumId: json['serverAlbumId'] as String?,
  );

  final String id;
  final int lidarrAlbumId;
  final String foreignAlbumId;
  final String albumTitle;
  final String artistName;
  final LidarrAction action;
  final DateTime createdAt;
  final String? coverUrl;
  final String? playlistId;
  final String? playlistName;

  /// The tracks the user asked for, or null for the whole album.
  final List<WantedTrack>? wanted;

  /// Set when the album already had files before this request, so nothing
  /// gets deleted while trimming it down to [wanted].
  final bool keepExistingFiles;
  final LidarrStage stage;
  final double? progress;
  final String? message;
  final bool trimmed;
  final String? serverAlbumId;

  bool get isActive => stage != LidarrStage.done && stage != LidarrStage.failed;

  String get displayName {
    final wanted = this.wanted;
    if (wanted == null || wanted.isEmpty) return albumTitle;
    if (wanted.length == 1) return wanted.first.title;
    return '$albumTitle (${wanted.length} songs)';
  }

  String get statusLabel => switch (stage) {
    LidarrStage.searching => message ?? 'Searching on Lidarr…',
    LidarrStage.downloading =>
      progress == null
          ? 'Downloading to server…'
          : 'Downloading to server ${(progress! * 100).round()}%',
    LidarrStage.waitingForServer => 'Waiting for the server to scan it…',
    LidarrStage.downloadingToDevice => 'Downloading to this device…',
    LidarrStage.done => switch (action) {
      LidarrAction.library => 'Added to your library',
      LidarrAction.download => 'Downloaded',
      LidarrAction.playlist => 'Added to ${playlistName ?? 'playlist'}',
    },
    LidarrStage.failed => message ?? 'Failed',
  };

  LidarrRequest copyWith({
    LidarrStage? stage,
    double? Function()? progress,
    String? Function()? message,
    bool? trimmed,
    String? serverAlbumId,
  }) => LidarrRequest(
    id: id,
    lidarrAlbumId: lidarrAlbumId,
    foreignAlbumId: foreignAlbumId,
    albumTitle: albumTitle,
    artistName: artistName,
    action: action,
    createdAt: createdAt,
    coverUrl: coverUrl,
    playlistId: playlistId,
    playlistName: playlistName,
    wanted: wanted,
    keepExistingFiles: keepExistingFiles,
    stage: stage ?? this.stage,
    progress: progress != null ? progress() : this.progress,
    message: message != null ? message() : this.message,
    trimmed: trimmed ?? this.trimmed,
    serverAlbumId: serverAlbumId ?? this.serverAlbumId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'lidarrAlbumId': lidarrAlbumId,
    'foreignAlbumId': foreignAlbumId,
    'albumTitle': albumTitle,
    'artistName': artistName,
    'action': action.name,
    'createdAt': createdAt.toIso8601String(),
    'coverUrl': coverUrl,
    'playlistId': playlistId,
    'playlistName': playlistName,
    'wanted': wanted?.map((track) => track.toJson()).toList(),
    'keepExistingFiles': keepExistingFiles,
    'stage': stage.name,
    'message': message,
    'trimmed': trimmed,
    'serverAlbumId': serverAlbumId,
  };
}

/// Tracks albums requested from Lidarr and carries each one through to the
/// action the user picked: polls Lidarr until the files are imported, trims
/// the album down to the requested songs, waits for the media server to
/// scan them in, then downloads them or adds them to a playlist.
class LidarrRequestsNotifier extends StateNotifier<List<LidarrRequest>> {
  LidarrRequestsNotifier(this._ref) : super(const []) {
    unawaited(_load());
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_tick()));
  }

  static const _storageKey = 'lidarr_requests';
  static const _pollInterval = Duration(seconds: 15);

  /// Lidarr sometimes can't find every track of an album. Once nothing is
  /// queued and some files exist, stop waiting for the rest after this long.
  static const _settleAfter = Duration(minutes: 10);

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  var _ticking = false;
  final _lastQueued = <String, DateTime>{};
  final _lastSearch = <String, DateTime>{};
  final _releaseChecked = <String>{};
  final _lastDiagnosis = <String, DateTime>{};
  static const _diagnoseAfter = Duration(minutes: 3);
  static const _researchAfter = Duration(minutes: 15);
  final _deviceDownloads = <String>{};
  var _serverScanCounter = 0;

  LidarrClient? get _lidarr => _ref.read(lidarrClientProvider);

  MediaServerClient get _server => _ref.read(mediaServerClientProvider);

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(_storageKey);
      if (raw != null && mounted) {
        final cutoff = DateTime.now().subtract(const Duration(days: 2));
        state =
            [
                  for (final json in jsonDecode(raw) as List)
                    LidarrRequest.fromJson(
                      (json as Map).cast<String, dynamic>(),
                    ),
                ]
                .where((r) => r.isActive || r.createdAt.isAfter(cutoff))
                // A device download cut short by the app closing starts over.
                .map(
                  (r) => r.stage == LidarrStage.downloadingToDevice
                      ? r.copyWith(stage: LidarrStage.waitingForServer)
                      : r,
                )
                .toList();
      }
    } on Object catch (error) {
      debugPrint('[Lidarr] could not restore requests: $error');
    }
    _schedule();
  }

  Future<void> _save() async {
    try {
      final prefs = await _ref.read(sharedPreferencesProvider.future);
      await prefs.setString(
        _storageKey,
        jsonEncode([for (final request in state) request.toJson()]),
      );
    } on Object catch (error) {
      debugPrint('[Lidarr] could not save requests: $error');
    }
  }

  void _schedule() {
    final active = state.any((request) => request.isActive);
    if (!active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void _update(LidarrRequest request) {
    if (!mounted) return;
    final previous = state.where((r) => r.id == request.id).firstOrNull;
    if (previous?.stage != request.stage) {
      debugPrint(
        '[Lidarr] ${request.albumTitle}: ${previous?.stage.name} -> '
        '${request.stage.name}${request.message == null ? '' : ' (${request.message})'}',
      );
    }
    state = [
      for (final existing in state)
        if (existing.id == request.id) request else existing,
    ];
    unawaited(_save());
    _schedule();
  }

  /// Asks Lidarr for [album] and remembers what to do once it arrives.
  /// Pass [wanted] to keep only some of its tracks.
  Future<LidarrRequest> request({
    required LidarrAlbum album,
    required LidarrAction action,
    List<LidarrTrack>? wanted,
    LibraryItem? playlist,
  }) async {
    final lidarr = _lidarr;
    if (lidarr == null) throw const LidarrException('Connect Lidarr first');
    final hadFiles = album.isInLidarr && album.trackFileCount > 0;
    final added = await lidarr.addAlbum(album);
    final request = LidarrRequest(
      id: '${added.id}-${DateTime.now().microsecondsSinceEpoch}',
      lidarrAlbumId: added.id,
      foreignAlbumId: added.foreignAlbumId,
      albumTitle: added.title.isNotEmpty ? added.title : album.title,
      artistName: added.artistName.isNotEmpty
          ? added.artistName
          : album.artistName,
      coverUrl: album.coverUrl ?? added.coverUrl,
      action: action,
      createdAt: DateTime.now(),
      playlistId: playlist?.id,
      playlistName: playlist?.name,
      wanted: wanted == null
          ? null
          : [
              for (final track in wanted)
                WantedTrack(title: track.title, recordingId: track.recordingId),
            ],
      keepExistingFiles: hadFiles,
    );
    state = [request, ...state];
    await _save();
    _schedule();
    unawaited(_tick());
    return request;
  }

  void dismiss(String id) {
    state = [
      for (final request in state)
        if (request.id != id) request,
    ];
    unawaited(_save());
    _schedule();
  }

  Future<void> _tick() async {
    if (_ticking || !mounted) return;
    final lidarr = _lidarr;
    final active = state.where((request) => request.isActive).toList();
    if (lidarr == null || active.isEmpty) return;
    _ticking = true;
    try {
      List<LidarrQueueItem>? queue;
      for (final request in active) {
        try {
          if (request.stage == LidarrStage.searching ||
              request.stage == LidarrStage.downloading) {
            queue ??= await lidarr.queue();
            await _checkLidarr(lidarr, request, queue);
          } else if (request.stage == LidarrStage.waitingForServer) {
            await _checkServer(request);
          }
        } on LidarrException catch (error) {
          debugPrint('[Lidarr] ${request.albumTitle}: $error');
        } on Object catch (error, stackTrace) {
          debugPrint('[Lidarr] ${request.albumTitle}: $error\n$stackTrace');
        }
      }
    } finally {
      _ticking = false;
    }
  }

  Future<void> _checkLidarr(
    LidarrClient lidarr,
    LidarrRequest request,
    List<LidarrQueueItem> queue,
  ) async {
    final queued = queue
        .where((item) => item.albumId == request.lidarrAlbumId)
        .toList();
    if (queued.isNotEmpty) {
      _lastQueued[request.id] = DateTime.now();
      final sizes = queued.fold(0.0, (sum, item) => sum + item.size);
      final left = queued.fold(0.0, (sum, item) => sum + item.sizeLeft);
      _update(
        request.copyWith(
          stage: LidarrStage.downloading,
          progress: () =>
              sizes > 0 ? (1 - left / sizes).clamp(0.0, 1.0).toDouble() : null,
        ),
      );
      return;
    }

    final LidarrAlbum album;
    try {
      album = await lidarr.album(request.lidarrAlbumId);
    } on LidarrException catch (error) {
      if (!error.isNotFound) rethrow;
      _update(
        request.copyWith(
          stage: LidarrStage.failed,
          message: () =>
              'Lidarr removed this album. Its metadata profile may leave out '
              'EPs, singles or soundtracks.',
        ),
      );
      return;
    }
    final tracks = await lidarr.tracks(request.lidarrAlbumId);
    final wanted = request.wanted;
    final bool ready;
    if (wanted != null && wanted.isNotEmpty) {
      final matched = tracks
          .where((track) => wanted.any((w) => w.matchesTrack(track)))
          .toList();
      ready = matched.isNotEmpty
          ? matched.every((track) => track.hasFile)
          : _albumSettled(request, album);
    } else {
      ready = _albumSettled(request, album);
    }
    if (!ready) {
      debugPrint(
        '[Lidarr] ${request.albumTitle}: waiting, monitored=${album.monitored} '
        'files=${album.trackFileCount}/${album.trackCount}',
      );
      await _checkRelease(lidarr, request, album, tracks);
      await _nudge(lidarr, request, album);
      await _diagnose(lidarr, request, album);
      if (request.stage != LidarrStage.searching) {
        _update(request.copyWith(stage: LidarrStage.searching));
      }
      return;
    }
    debugPrint('[Lidarr] ${request.albumTitle}: imported, moving on');

    var next = request;
    if (wanted != null && wanted.isNotEmpty && !request.trimmed) {
      if (!request.keepExistingFiles) {
        // Stop Lidarr from fetching the deleted tracks again.
        await lidarr.setMonitored([request.lidarrAlbumId], monitored: false);
        await lidarr.deleteTrackFiles([
          for (final track in tracks)
            if (track.hasFile &&
                track.trackFileId > 0 &&
                !wanted.any((w) => w.matchesTrack(track)))
              track.trackFileId,
        ]);
      }
      next = next.copyWith(trimmed: true);
    }

    unawaited(_refreshServer());
    if (request.action == LidarrAction.library) {
      _update(next.copyWith(stage: LidarrStage.done, progress: () => 1));
    } else {
      _update(
        next.copyWith(stage: LidarrStage.waitingForServer, progress: () => 1),
      );
    }
  }

  /// Lidarr grabs one edition of an album. Make sure it's one that has the
  /// requested songs (a bonus track may only be on the deluxe edition).
  Future<void> _checkRelease(
    LidarrClient lidarr,
    LidarrRequest request,
    LidarrAlbum album,
    List<LidarrTrack> monitoredTracks,
  ) async {
    final wanted = request.wanted;
    if (wanted == null || wanted.isEmpty) return;
    if (!_releaseChecked.add(request.id)) return;
    bool hasAll(List<LidarrTrack> tracks) =>
        wanted.every((w) => tracks.any(w.matchesTrack));
    if (hasAll(monitoredTracks)) return;
    for (final release in album.releases.take(12)) {
      if (release.monitored) continue;
      final tracks = await lidarr.releaseTracks(release.id);
      if (!hasAll(tracks)) continue;
      debugPrint(
        '[Lidarr] ${request.albumTitle}: switching to release ${release.id}, '
        'which has the requested songs',
      );
      if (await lidarr.monitorRelease(album.id, release.id)) {
        await lidarr.searchAlbum(album.id);
      }
      return;
    }
    debugPrint(
      '[Lidarr] ${request.albumTitle}: no release lists every requested song',
    );
  }

  /// When a search has had a few minutes and nothing is downloading, asks
  /// Lidarr what its indexers found, so the request can say why.
  Future<void> _diagnose(
    LidarrClient lidarr,
    LidarrRequest request,
    LidarrAlbum album,
  ) async {
    final age = DateTime.now().difference(request.createdAt);
    if (age < _diagnoseAfter || _lastQueued.containsKey(request.id)) return;
    final last = _lastDiagnosis[request.id];
    if (last != null && DateTime.now().difference(last) < _researchAfter) {
      return;
    }
    _lastDiagnosis[request.id] = DateTime.now();
    final candidates = await lidarr.releaseCandidates(album.id);
    final usable = candidates.where((c) => !c.rejected).length;
    final reasons = <String, int>{};
    for (final candidate in candidates.where((c) => c.rejected)) {
      for (final reason in candidate.rejections) {
        reasons[reason] = (reasons[reason] ?? 0) + 1;
      }
    }
    final topReason =
        (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .firstOrNull
            ?.key;
    debugPrint(
      '[Lidarr] ${request.albumTitle}: indexers returned '
      '${candidates.length} releases, $usable usable. Rejections: $reasons',
    );
    for (final candidate in candidates.take(10)) {
      debugPrint(
        '[Lidarr]   ${candidate.rejected ? 'rejected' : 'ok'} '
        '${candidate.title} ${candidate.rejections}',
      );
    }
    final message = candidates.isEmpty
        ? 'Lidarr\'s indexers found no releases for this album'
        : usable > 0
        ? 'Lidarr found $usable usable releases. It should grab one soon'
        : 'Lidarr found ${candidates.length} releases but rejected them all'
              '${topReason == null ? '' : ': $topReason'}';
    final current = state.where((r) => r.id == request.id).firstOrNull;
    if (current != null && current.isActive) {
      _update(current.copyWith(message: () => message));
    }
  }

  /// Keeps a stalled request alive: Lidarr can unmonitor an album while it
  /// refreshes a newly added artist, and a search can come up empty until
  /// a release appears on an indexer.
  Future<void> _nudge(
    LidarrClient lidarr,
    LidarrRequest request,
    LidarrAlbum album,
  ) async {
    final last = _lastSearch[request.id];
    final unmonitored = !album.monitored && !request.trimmed;
    final stale =
        last == null || DateTime.now().difference(last) > _researchAfter;
    if (!unmonitored && !stale) return;
    _lastSearch[request.id] = DateTime.now();
    if (unmonitored) {
      debugPrint('[Lidarr] ${request.albumTitle}: was unmonitored, fixing');
      await lidarr.setMonitored([album.id], monitored: true);
    }
    await lidarr.searchAlbum(album.id);
  }

  bool _albumSettled(LidarrRequest request, LidarrAlbum album) {
    final files = album.trackFileCount;
    if (files <= 0) return false;
    if (album.trackCount > 0 && files >= album.trackCount) return true;
    final lastQueued = _lastQueued[request.id];
    return lastQueued != null &&
        DateTime.now().difference(lastQueued) > _settleAfter;
  }

  Future<void> _refreshServer() async {
    try {
      await _server.refreshLibrary();
    } on Object catch (error) {
      debugPrint('[Lidarr] media server refresh failed: $error');
    }
  }

  Future<void> _checkServer(LidarrRequest request) async {
    if (_deviceDownloads.contains(request.id)) return;
    final server = _server;
    final album = await _findServerAlbum(server, request);
    if (album == null) {
      // Nudge the server every minute or so in case it isn't watching
      // the library folder for changes.
      if (++_serverScanCounter % 4 == 0) unawaited(_refreshServer());
      return;
    }

    final songs = [...(await server.getSongs(album.id)).items]
      ..sort(LibraryItem.compareAlbumOrder);
    final wanted = request.wanted;
    final picked = wanted == null || wanted.isEmpty
        ? songs
        : songs
              .where((song) => wanted.any((w) => w.matchesSong(song)))
              .toList();
    final expected = wanted == null || wanted.isEmpty ? 1 : wanted.length;
    if (picked.length < expected) return;

    switch (request.action) {
      case LidarrAction.library:
        _update(request.copyWith(stage: LidarrStage.done));
      case LidarrAction.playlist:
        final playlistId = request.playlistId;
        if (playlistId == null) {
          _update(
            request.copyWith(
              stage: LidarrStage.failed,
              message: () => 'No playlist was chosen',
            ),
          );
          return;
        }
        await server.addPlaylistItems(
          playlistId: playlistId,
          itemIds: [for (final song in picked) song.id],
        );
        _ref.read(downloadSyncProvider).syncPlaylist(playlistId);
        _update(
          request.copyWith(stage: LidarrStage.done, serverAlbumId: album.id),
        );
      case LidarrAction.download:
        _deviceDownloads.add(request.id);
        _update(
          request.copyWith(
            stage: LidarrStage.downloadingToDevice,
            serverAlbumId: album.id,
            progress: () => null,
          ),
        );
        final manager = _ref.read(downloadManagerProvider);
        try {
          if (wanted == null || wanted.isEmpty) {
            await manager.downloadAlbum(album, picked);
          } else {
            for (final song in picked) {
              await manager.downloadSong(song);
            }
          }
        } finally {
          _deviceDownloads.remove(request.id);
        }
        final current = state.where((r) => r.id == request.id).firstOrNull;
        if (current != null) {
          _update(current.copyWith(stage: LidarrStage.done));
        }
    }
  }

  Future<LibraryItem?> _findServerAlbum(
    MediaServerClient server,
    LidarrRequest request,
  ) async {
    final page = await server.searchAlbums(
      SearchQuery(term: request.albumTitle, limit: 25),
    );
    final title = normalizeTitle(request.albumTitle);
    final artist = normalizeTitle(request.artistName);
    LibraryItem? byName;
    for (final album in page.items) {
      final ids = album.externalIds;
      if (request.foreignAlbumId.isNotEmpty &&
          ids[ExternalIdProvider.musicBrainzReleaseGroup] ==
              request.foreignAlbumId) {
        return album;
      }
      final albumArtist = normalizeTitle(
        album.albumArtist ?? album.artistLabel,
      );
      final artistMatches =
          artist.isEmpty ||
          albumArtist.contains(artist) ||
          artist.contains(albumArtist);
      if (normalizeTitle(album.name) == title && artistMatches) {
        byName ??= album;
      }
    }
    return byName;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }
}

final lidarrRequestsProvider =
    StateNotifierProvider<LidarrRequestsNotifier, List<LidarrRequest>>(
      LidarrRequestsNotifier.new,
    );

final activeLidarrRequestsProvider = Provider<List<LidarrRequest>>(
  (ref) => [
    for (final request in ref.watch(lidarrRequestsProvider))
      if (request.isActive || request.stage == LidarrStage.failed) request,
  ],
);
