import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/domain/providers/player_bar_provider.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/ipod/click_wheel.dart';
import 'package:jplayer/src/presentation/ipod/ipod_screens.dart';

/// A screen shown on the iPod display. The shell forwards click wheel
/// input to the top-most screen.
abstract class IpodScreenState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  void onScroll(int step) {}

  void onSelect() {}

  /// Return true when the screen handled MENU itself instead of going back.
  bool onMenu() => false;

  /// Return true when the screen handled play/pause itself.
  bool onPlayPause() => false;
}

class IpodPage {
  IpodPage({required this.title, required this.builder, this.showArt = false});

  final String title;
  final Widget Function(GlobalKey key) builder;

  /// Split the display with cover art, like the classic main menu.
  final bool showArt;
  final GlobalKey key = GlobalKey();

  late final Widget widget = KeyedSubtree(
    key: ValueKey(key),
    child: builder(key),
  );
}

class IpodNavigator extends InheritedWidget {
  const IpodNavigator({required this.shell, required super.child, super.key});

  final IpodShellState shell;

  static IpodShellState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IpodNavigator>()!.shell;

  @override
  bool updateShouldNotify(IpodNavigator oldWidget) => shell != oldWidget.shell;
}

/// The whole app re-imagined as an iPod classic: a display with nested
/// menus above a click wheel.
class IpodShell extends ConsumerStatefulWidget {
  const IpodShell({super.key});

  @override
  ConsumerState<IpodShell> createState() => IpodShellState();
}

class IpodShellState extends ConsumerState<IpodShell> {
  late final List<IpodPage> _stack = [mainMenuPage()];
  var _forward = true;

  IpodPage get top => _stack.last;

  bool get haptics => ref.read(settingProvider(AppSetting.ipodHaptics));

  IpodScreenState? get _screen => top.key.currentState as IpodScreenState?;

  void push(IpodPage page) => setState(() {
    _forward = true;
    _stack.add(page);
  });

  void pop() {
    if (_stack.length <= 1) return;
    setState(() {
      _forward = false;
      _stack.removeLast();
    });
  }

  void popToRoot() {
    if (_stack.length <= 1) return;
    setState(() {
      _forward = false;
      _stack.removeRange(1, _stack.length);
    });
  }

  /// Shows Now Playing, reusing it if it's already on the stack.
  void openNowPlaying() {
    final index = _stack.indexWhere((page) => page.title == 'Now Playing');
    if (index >= 0) {
      setState(() {
        _forward = index != _stack.length - 1;
        _stack
          ..removeRange(index + 1, _stack.length)
          ..add(_stack.removeAt(index));
      });
      return;
    }
    push(nowPlayingPage());
  }

  void _onScroll(int step) => _screen?.onScroll(step);

  void _onButton(WheelButton button) {
    final controls = ref.read(barControlsProvider);
    switch (button) {
      case WheelButton.menu:
        if (!(_screen?.onMenu() ?? false)) pop();
      case WheelButton.select:
        _screen?.onSelect();
      case WheelButton.playPause:
        if (!(_screen?.onPlayPause() ?? false)) controls.togglePlay().ignore();
      case WheelButton.next:
        controls.next().ignore();
      case WheelButton.previous:
        controls.previous().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(settingProvider(AppSetting.ipodBlack));
    final haptics = ref.watch(settingProvider(AppSetting.ipodHaptics));
    final size = MediaQuery.sizeOf(context);
    final width = size.width.clamp(0.0, 460.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IpodNavigator(
        shell: this,
        child: Scaffold(
          backgroundColor: dark
              ? const Color(0xFF111112)
              : const Color(0xFFD9D9DB),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [Color(0xFF2A2A2C), Color(0xFF0E0E0F)]
                    : const [Color(0xFFE6E6E8), Color(0xFFC9C9CC)],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          width * 0.045,
                          width * 0.03,
                          width * 0.045,
                          0,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1.32,
                          child: _display(),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: ClickWheel(
                            size: width * 0.74,
                            haptics: haptics,
                            dark: dark,
                            onScroll: _onScroll,
                            onButton: _onButton,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _display() => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1C),
      borderRadius: BorderRadius.circular(5),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: DefaultTextStyle(
        style: ipodTextStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBar(title: top.title),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: _slide,
                layoutBuilder: (current, previous) => Stack(
                  children: [...previous, ?current],
                ),
                child: _page(top),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _page(IpodPage page) => KeyedSubtree(
    key: ValueKey(page.key),
    child: page.showArt
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: page.widget),
              const Expanded(child: IpodArtPanel()),
            ],
          )
        : page.widget,
  );

  Widget _slide(Widget child, Animation<double> animation) {
    final incoming = child.key == ValueKey(top.key);
    // Pushing slides the new screen in from the right and the old one out
    // to the left; going back does the opposite.
    final from = incoming ? (_forward ? 1.0 : -1.0) : (_forward ? -1.0 : 1.0);
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(from, 0),
          end: Offset.zero,
        ).animate(animation),
        child: ColoredBox(color: Colors.white, child: child),
      ),
    );
  }
}

const ipodTextStyle = TextStyle(
  fontFamily: 'Helvetica Neue',
  color: Colors.black,
  fontSize: 17,
  fontWeight: FontWeight.w600,
  height: 1.15,
  letterSpacing: -0.2,
);

class _StatusBar extends ConsumerStatefulWidget {
  const _StatusBar({required this.title});

  final String title;

  @override
  ConsumerState<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<_StatusBar> {
  final _battery = Battery();
  Timer? _timer;
  var _level = 100;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _read());
  }

  Future<void> _read() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) setState(() => _level = level);
    } on Object {
      // Simulators and some devices don't report a level.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = ref.watch(barPlayingProvider);
    final hasSong = ref.watch(barSongProvider) != null;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFCFC), Color(0xFFD3D4D7)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF8E9094))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ipodTextStyle.copyWith(fontSize: 14),
            ),
          ),
          if (hasSong)
            Icon(
              playing ? Icons.play_arrow : Icons.pause,
              size: 16,
              color: const Color(0xFF5A6E8C),
            ),
          const SizedBox(width: 4),
          _BatteryGlyph(level: _level),
        ],
      ),
    );
  }
}

class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final fraction = (level / 100).clamp(0.08, 1.0);
    final color = level <= 20
        ? const Color(0xFFE0402C)
        : const Color(0xFF4CC33B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 12,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF6B6B6B)),
            borderRadius: BorderRadius.circular(2),
            color: Colors.white,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(color, Colors.white, 0.4)!, color],
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(width: 2, height: 5, color: const Color(0xFF6B6B6B)),
      ],
    );
  }
}
