import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/core/enums/enums.dart';
import 'package:jplayer/src/domain/providers/player_bar_provider.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/ipod/click_wheel.dart';
import 'package:jplayer/src/presentation/ipod/ipod_screens.dart';
import 'package:jplayer/src/presentation/ipod/sansa_controls.dart';

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

/// Tells the retro screens which device they're drawn on.
class RetroSkinScope extends InheritedWidget {
  const RetroSkinScope({required this.sansa, required super.child, super.key});

  final bool sansa;

  static bool isSansa(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RetroSkinScope>()?.sansa ??
      false;

  @override
  bool updateShouldNotify(RetroSkinScope oldWidget) => sansa != oldWidget.sansa;
}

/// The whole app re-imagined as a classic music player: an iPod classic
/// ("Cupertino") or a Sansa e200 ("Not Cupertino"), with nested menus
/// above a scroll wheel.
class IpodShell extends ConsumerStatefulWidget {
  const IpodShell({super.key});

  @override
  ConsumerState<IpodShell> createState() => IpodShellState();
}

class IpodShellState extends ConsumerState<IpodShell> {
  late bool _sansa = ref.read(retroThemeProvider) == RetroTheme.sansa;
  late final List<IpodPage> _stack = [mainMenuPage(sansa: _sansa)];
  var _forward = true;

  bool get _onNowPlaying => top.title == 'Now Playing';

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
    // On the Sansa, previous/next move back and forward through menus and
    // only skip tracks on Now Playing.
    if (_sansa && !_onNowPlaying) {
      if (button == WheelButton.previous) button = WheelButton.menu;
      if (button == WheelButton.next) button = WheelButton.select;
    }
    switch (button) {
      case WheelButton.home:
        popToRoot();
      case WheelButton.options:
        if (top.title == 'Music Options') {
          pop();
        } else {
          push(musicOptionsPage());
        }
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
    ref.listen<RetroTheme>(retroThemeProvider, (_, theme) {
      final sansa = theme == RetroTheme.sansa;
      if (theme == RetroTheme.off || sansa == _sansa) return;
      setState(() {
        _sansa = sansa;
        _forward = false;
        _stack
          ..clear()
          ..add(mainMenuPage(sansa: sansa));
      });
    });
    if (_sansa) return _sansaBody(context);
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

  Widget _sansaBody(BuildContext context) {
    final haptics = ref.watch(settingProvider(AppSetting.ipodHaptics));
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 460.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: IpodNavigator(
        shell: this,
        child: RetroSkinScope(
          sansa: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: DecoratedBox(
              // Glossy black plastic.
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF26272B),
                    Color(0xFF050506),
                    Color(0xFF151518),
                  ],
                  stops: [0, 0.55, 1],
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
                            width * 0.07,
                            width * 0.03,
                            width * 0.07,
                            0,
                          ),
                          child: AspectRatio(
                            aspectRatio: 1.02,
                            child: _sansaDisplay(),
                          ),
                        ),
                        SizedBox(height: width * 0.04),
                        Text(
                          'sansa',
                          style: TextStyle(
                            fontFamily: 'Arial',
                            fontSize: width * 0.065,
                            letterSpacing: 1.5,
                            color: const Color(0xFFCFD0D5),
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SansaControls(
                                size: width * 0.72,
                                haptics: haptics,
                                onScroll: _onScroll,
                                onButton: _onButton,
                              ),
                              Positioned(
                                left: width * 0.01,
                                bottom: 0,
                                child: SansaMenuButton(
                                  size: width * 0.1,
                                  haptics: haptics,
                                  onPressed: () => _onButton(WheelButton.home),
                                ),
                              ),
                            ],
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
      ),
    );
  }

  Widget _sansaDisplay() => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: const Color(0xFF3A3B40),
      borderRadius: BorderRadius.circular(6),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: DefaultTextStyle(
        style: sansaTextStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (top.title.isNotEmpty) _SansaTitleBar(title: top.title),
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
            const _SansaStatusBar(),
          ],
        ),
      ),
    ),
  );

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
        child: _sansa
            ? SansaScreenBackground(child: child)
            : ColoredBox(color: Colors.white, child: child),
      ),
    );
  }
}

const sansaTextStyle = TextStyle(
  fontFamily: 'Arial',
  color: Color(0xFF14284B),
  fontSize: 17,
  fontWeight: FontWeight.w700,
  height: 1.15,
);

/// The Sansa's screen: a sky-blue gradient with the curved gloss sweep
/// across its lower half.
class SansaScreenBackground extends StatelessWidget {
  const SansaScreenBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _SansaGlossPainter(), child: child);
}

class _SansaGlossPainter extends CustomPainter {
  const _SansaGlossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB3D7F0), Color(0xFF7DB5E1), Color(0xFF5596CF)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    // The gloss: a curve rising from the left edge to the right, with a
    // soft lighter band under it.
    final w = size.width;
    final h = size.height;
    final curve = Path()
      ..moveTo(0, h * 0.74)
      ..quadraticBezierTo(w * 0.45, h * 0.68, w, h * 0.55);
    final band = Path.from(curve)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas
      ..drawPath(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.2),
              Colors.white.withValues(alpha: 0.04),
            ],
          ).createShader(Rect.fromLTWH(0, h * 0.55, w, h * 0.45)),
      )
      ..drawPath(
        curve,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );
  }

  @override
  bool shouldRepaint(_SansaGlossPainter oldDelegate) => false;
}

class _SansaTitleBar extends StatelessWidget {
  const _SansaTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5B8FDA), Color(0xFF2551A6)],
      ),
    ),
    child: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: sansaTextStyle.copyWith(color: Colors.white, fontSize: 16),
    ),
  );
}

/// The Sansa's bottom strip: play state, the time and the battery.
class _SansaStatusBar extends ConsumerStatefulWidget {
  const _SansaStatusBar();

  @override
  ConsumerState<_SansaStatusBar> createState() => _SansaStatusBarState();
}

class _SansaStatusBarState extends ConsumerState<_SansaStatusBar> {
  /// "10:26 pm", formatted by hand: intl's DateFormat needs locale data
  /// the app doesn't load, and threw on devices outside en_US.
  static String _clock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'am' : 'pm'}';
  }

  final _battery = Battery();
  Timer? _clockTimer;
  Timer? _batteryTimer;
  late final AppLifecycleListener _lifecycle;
  var _level = 100;
  var _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_readBattery());
    _batteryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _readBattery(),
    );
    _scheduleClock(initial: true);
    // Timers don't run in the background, so catch up on returning.
    _lifecycle = AppLifecycleListener(onResume: _scheduleClock);
  }

  /// Updates the time right as each minute starts, so it changes in step
  /// with the phone's own clock.
  void _scheduleClock({bool initial = false}) {
    _clockTimer?.cancel();
    if (!mounted) return;
    final now = DateTime.now();
    if (initial) {
      _now = now;
    } else {
      setState(() => _now = now);
    }
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _clockTimer = Timer(
      nextMinute.difference(now) + const Duration(milliseconds: 20),
      _scheduleClock,
    );
  }

  Future<void> _readBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) setState(() => _level = level);
    } on Object {
      // Simulators and some devices don't report a level.
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _batteryTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = ref.watch(barPlayingProvider);
    final hasSong = ref.watch(barSongProvider) != null;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        // Brushed silver, like the e200's bottom strip.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCBD3DB), Color(0xFFA3AEB9), Color(0xFF8B97A3)],
          stops: [0, 0.5, 1],
        ),
        border: Border(top: BorderSide(color: Color(0xFFE6ECF1))),
      ),
      child: Row(
        children: [
          if (hasSong) ...[
            Icon(
              playing ? Icons.play_arrow : Icons.pause,
              size: 15,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            _clock(_now),
            style: sansaTextStyle.copyWith(
              color: Colors.white,
              fontSize: 15,
              shadows: const [
                Shadow(color: Color(0x80404A55), offset: Offset(0, 1)),
              ],
            ),
          ),
          const Spacer(),
          _BatteryGlyph(level: _level),
        ],
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
