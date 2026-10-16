import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/domain/providers/lidarr_account_provider.dart';
import 'package:jplayer/src/presentation/widgets/form_modal.dart';
import 'package:jplayer/src/presentation/widgets/labeled_text_field.dart';

class LidarrSettings extends ConsumerWidget {
  const LidarrSettings({super.key});

  static final ButtonStyle _buttonStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(lidarrAccountProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onPrimary.withValues(alpha: 0.7);

    return switch (account.status) {
      LidarrStatus.loading => const SizedBox.shrink(),
      LidarrStatus.connected => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                'Connected to ${Uri.tryParse(account.url)?.host ?? account.url}',
                style: TextStyle(color: muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => unawaited(
              ref.read(lidarrAccountProvider.notifier).disconnect(),
            ),
            style: _buttonStyle,
            child: const Text('Disconnect'),
          ),
        ],
      ),
      LidarrStatus.disconnected || LidarrStatus.connecting => TextButton.icon(
        onPressed: account.status == LidarrStatus.connecting
            ? null
            : () => unawaited(
                showFormModal<void>(
                  context,
                  builder: (context) => const LidarrConnectForm(),
                ),
              ),
        style: _buttonStyle,
        icon: const Icon(Icons.link),
        label: const Text('Connect Lidarr'),
      ),
    };
  }
}

class LidarrConnectForm extends ConsumerStatefulWidget {
  const LidarrConnectForm({super.key});

  @override
  ConsumerState<LidarrConnectForm> createState() => _LidarrConnectFormState();
}

class _LidarrConnectFormState extends ConsumerState<LidarrConnectForm> {
  late final _urlController = TextEditingController(
    text: ref.read(lidarrAccountProvider).url,
  );
  final _keyController = TextEditingController();
  String? _error;
  var _submitting = false;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final connected = await ref
        .read(lidarrAccountProvider.notifier)
        .connect(url: _urlController.text, apiKey: _keyController.text);
    if (!mounted) return;
    if (connected) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = ref.read(lidarrAccountProvider).error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModalFormHeader('Connect Lidarr'),
          const SizedBox(height: 8),
          Text(
            'Search for albums on Lidarr and add them to your server. Find '
            'the API key in Lidarr under Settings › General.',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          LabeledTextField(
            controller: _urlController,
            label: 'Address',
            placeholder: 'http://192.168.1.10:8686',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          LabeledTextField(
            controller: _keyController,
            label: 'API key',
            placeholder: 'API key',
            obscureText: true,
            textInputAction: TextInputAction.done,
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          ModalFormActions(
            submitLabel: 'Connect',
            onSubmit: () => unawaited(_submit()),
            busy: _submitting,
          ),
        ],
      ),
    );
  }
}
