import 'package:flutter/material.dart';
import 'package:jplayer/src/config/constants.dart';
import 'package:jplayer/src/presentation/themes/themes.dart';
import 'package:updatify_flutter/updatify_flutter.dart';

/// A note that something comes from the upstream JellyBox app rather than
/// from this fork.
class UpstreamNotice extends StatelessWidget {
  const UpstreamNotice({required this.message, this.margin, super.key});

  final String message;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.tertiary),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

const _announcementsNotice =
    'These announcements are about the upstream JellyBox app. PuddingCup is '
    'a fork, so features mentioned here, like Jellybox Cloud, may or may not '
    'work in it.';

/// Opens the upstream JellyBox "What's new" posts, with a note above them
/// that they describe JellyBox rather than this fork.
Future<void> showUpstreamAnnouncements(
  BuildContext context, {
  required bool isDesktop,
  UpdatifyService? service,
}) {
  final radius = BorderRadius.circular(8);
  Widget header(BuildContext context, TextStyle? style) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Expanded(child: Text(changelogTitle, style: style)),
        const CloseButton(),
      ],
    ),
  );
  Widget posts() => UpdatifyWidget(
    projectId: updatifyProjectId,
    service: service,
    padding: const EdgeInsets.only(bottom: 16),
    poweredByAlignment: isDesktop
        ? MainAxisAlignment.end
        : MainAxisAlignment.center,
  );
  const notice = UpstreamNotice(
    message: _announcementsNotice,
    margin: EdgeInsets.fromLTRB(16, 12, 16, 4),
  );

  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Themes.changelogSurface,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        titlePadding: EdgeInsets.zero,
        title: header(context, null),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width / 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              notice,
              Flexible(child: posts()),
            ],
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Themes.changelogSurface,
    shape: RoundedRectangleBorder(borderRadius: radius),
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header(context, Theme.of(context).textTheme.titleLarge),
          notice,
          Flexible(child: posts()),
        ],
      ),
    ),
  );
}
