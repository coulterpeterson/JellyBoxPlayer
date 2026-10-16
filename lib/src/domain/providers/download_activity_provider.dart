import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/enums/download_status.dart';
import 'package:jplayer/src/domain/models/models.dart';

class DownloadActivity {
  const DownloadActivity({
    this.collections = const {},
    this.songs = const {},
    this.pending = const {},
  });

  final Map<String, double> collections;
  final Map<String, DownloadTask> songs;

  /// Albums, playlists and songs the user asked to download that haven't
  /// finished yet, in the order they were requested.
  final Map<String, LibraryItem> pending;

  DownloadActivity copyWith({
    Map<String, double>? collections,
    Map<String, DownloadTask>? songs,
    Map<String, LibraryItem>? pending,
  }) => DownloadActivity(
    collections: collections ?? this.collections,
    songs: songs ?? this.songs,
    pending: pending ?? this.pending,
  );
}

class DownloadActivityNotifier extends Notifier<DownloadActivity> {
  static const _settled = {
    DownloadStatus.completed,
    DownloadStatus.failed,
    DownloadStatus.canceled,
  };

  @override
  DownloadActivity build() => const DownloadActivity();

  void setCollectionProgress(String id, double? progress) {
    state = state.copyWith(
      collections: progress == null
          ? ({...state.collections}..remove(id))
          : {...state.collections, id: progress},
    );
  }

  void setPending(LibraryItem item) {
    state = state.copyWith(pending: {...state.pending, item.id: item});
  }

  void clearPending(String id) {
    if (!state.pending.containsKey(id)) return;
    state = state.copyWith(pending: {...state.pending}..remove(id));
  }

  void trackSong(DownloadTask task) {
    state = state.copyWith(songs: {...state.songs, task.id: task});
  }

  void untrackSong(String id) {
    if (!state.songs.containsKey(id)) return;
    state = state.copyWith(songs: {...state.songs}..remove(id));
  }

  void pruneSettled() {
    final live = {
      for (final MapEntry(:key, :value) in state.songs.entries)
        if (!_settled.contains(value.status.value)) key: value,
    };
    if (live.length != state.songs.length) state = state.copyWith(songs: live);
  }
}

final downloadActivityProvider =
    NotifierProvider<DownloadActivityNotifier, DownloadActivity>(
      DownloadActivityNotifier.new,
    );

final ProviderFamily<double?, String> downloadProgressProvider =
    Provider.family<double?, String>(
      (ref, id) => ref.watch(
        downloadActivityProvider.select((activity) => activity.collections[id]),
      ),
    );

final ProviderFamily<DownloadTask?, String> songDownloadTaskProvider =
    Provider.family<DownloadTask?, String>(
      (ref, id) => ref.watch(
        downloadActivityProvider.select((activity) => activity.songs[id]),
      ),
    );

final pendingDownloadsProvider = Provider<List<LibraryItem>>(
  (ref) => ref
      .watch(downloadActivityProvider.select((activity) => activity.pending))
      .values
      .toList(),
);
