import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/config/constants.dart';
import 'package:jplayer/src/presentation/widgets/hover_zoom.dart';
import 'package:jplayer/src/presentation/widgets/upstream_announcements.dart';
import 'package:jplayer/src/providers/color_scheme_provider.dart';
import 'package:updatify_flutter/updatify_flutter.dart';

class UpdatifyBell extends ConsumerStatefulWidget {
  const UpdatifyBell({
    required this.isDesktop,
    this.iconSize = 28,
    this.tapSize = 40,
    super.key,
  });

  final bool isDesktop;
  final double iconSize;
  final double tapSize;

  @override
  ConsumerState<UpdatifyBell> createState() => _UpdatifyBellState();
}

class _UpdatifyBellState extends ConsumerState<UpdatifyBell> {
  /// Bumped after the announcements close, so the trigger checks again and
  /// clears its dot.
  var _opens = 0;

  Future<void> _open() async {
    await showUpstreamAnnouncements(context, isDesktop: widget.isDesktop);
    if (mounted) setState(() => _opens++);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.iconSize;
    final tapSize = widget.tapSize;
    final accent = ref.watch(accentColorProvider);
    return HoverZoom(
      builder: (context, hovered) => IconTheme.merge(
        data: IconThemeData(size: iconSize),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.square(tapSize),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: hovered ? accent : null,
              overlayColor: Colors.transparent,
            ),
          ),
          child: UpdatifyTrigger(
            key: ValueKey(_opens),
            projectId: updatifyProjectId,
            builder: (context, hasNewUpdates, _) => IconButton(
              onPressed: () => unawaited(_open()),
              icon: Badge(
                isLabelVisible: hasNewUpdates,
                smallSize: 8,
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
