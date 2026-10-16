import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/lidarr/lidarr_client.dart';
import 'package:jplayer/src/data/providers/providers.dart';
import 'package:jplayer/src/data/storages/keychain_access.dart';
import 'package:jplayer/src/domain/providers/app_settings_provider.dart';

enum LidarrStatus { loading, disconnected, connecting, connected }

@immutable
class LidarrAccount {
  const LidarrAccount({
    required this.status,
    this.url = '',
    this.apiKey,
    this.version,
    this.error,
  });

  final LidarrStatus status;
  final String url;
  final String? apiKey;
  final String? version;
  final String? error;

  bool get isConnected => status == LidarrStatus.connected;
}

class LidarrAccountNotifier extends StateNotifier<LidarrAccount> {
  LidarrAccountNotifier(this._ref)
    : super(const LidarrAccount(status: LidarrStatus.loading)) {
    unawaited(_restore());
  }

  static const apiKeyKey = 'lidarr_api_key';

  final Ref _ref;
  var _attempt = 0;

  Future<void> _restore() async {
    final attempt = _attempt;
    try {
      await _ref.read(sharedPreferencesProvider.future);
      final url = _ref
          .read(appSettingsProvider.notifier)
          .valueOf(AppSetting.lidarrUrl);
      final apiKey = await KeychainAccess(
        _ref.read(secureStorageProvider),
      ).readSessionKey(apiKeyKey);
      if (!mounted || attempt != _attempt) return;
      if (url.isNotEmpty && apiKey != null && apiKey.isNotEmpty) {
        state = LidarrAccount(
          status: LidarrStatus.connected,
          url: url,
          apiKey: apiKey,
        );
        return;
      }
    } on Object catch (error) {
      debugPrint('[Lidarr] restoring the connection failed: $error');
    }
    if (mounted && attempt == _attempt) {
      state = const LidarrAccount(status: LidarrStatus.disconnected);
    }
  }

  Future<bool> connect({required String url, required String apiKey}) async {
    final endpoint = LidarrClient.normalizeUrl(url);
    final key = apiKey.trim();
    if (endpoint == null) return _fail('Enter your Lidarr address', url);
    if (key.isEmpty) return _fail('Enter your Lidarr API key', endpoint);

    final attempt = ++_attempt;
    state = LidarrAccount(status: LidarrStatus.connecting, url: endpoint);
    try {
      final version = await LidarrClient(
        baseUrl: endpoint,
        apiKey: key,
      ).systemVersion();
      if (!mounted || attempt != _attempt) return false;
      await _ref.read(secureStorageProvider).write(key: apiKeyKey, value: key);
      _ref
          .read(appSettingsProvider.notifier)
          .setValue(AppSetting.lidarrUrl, endpoint);
      state = LidarrAccount(
        status: LidarrStatus.connected,
        url: endpoint,
        apiKey: key,
        version: version,
      );
      return true;
    } on Object catch (error) {
      if (attempt != _attempt) return false;
      return _fail('Could not connect: $error', endpoint);
    }
  }

  Future<void> disconnect() async {
    _attempt++;
    state = const LidarrAccount(status: LidarrStatus.disconnected);
    _ref.read(appSettingsProvider.notifier).setValue(AppSetting.lidarrUrl, '');
    try {
      await _ref.read(secureStorageProvider).delete(key: apiKeyKey);
    } on Object catch (error) {
      debugPrint('[Lidarr] removing the API key failed: $error');
    }
  }

  bool _fail(String message, String url) {
    if (mounted) {
      state = LidarrAccount(
        status: LidarrStatus.disconnected,
        url: url,
        error: message,
      );
    }
    return false;
  }
}

final lidarrAccountProvider =
    StateNotifierProvider<LidarrAccountNotifier, LidarrAccount>(
      LidarrAccountNotifier.new,
    );

/// A client for the connected Lidarr server, or null when none is set up.
final lidarrClientProvider = Provider<LidarrClient?>((ref) {
  final account = ref.watch(lidarrAccountProvider);
  final apiKey = account.apiKey;
  if (!account.isConnected || apiKey == null) return null;
  return LidarrClient(baseUrl: account.url, apiKey: apiKey);
});
