import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum WheelButton {
  menu,
  next,
  previous,
  playPause,
  select,

  /// The Sansa's submenu (≡) button.
  options,

  /// The Sansa's power/menu button: back to the home screen.
  home,
}

/// A classic iPod click wheel. Dragging around the ring emits [onScroll]
/// ticks (+1 clockwise, -1 counter-clockwise) with a subtle haptic click
/// per tick; tapping the ring's compass points or the centre emits
/// [onButton].
class ClickWheel extends StatefulWidget {
  const ClickWheel({
    required this.size,
    required this.onScroll,
    required this.onButton,
    this.haptics = true,
    this.dark = false,
    super.key,
  });

  final double size;
  final ValueChanged<int> onScroll;
  final ValueChanged<WheelButton> onButton;
  final bool haptics;
  final bool dark;

  /// How far the finger travels around the ring for one tick.
  static const tickAngle = math.pi / 10;

  @override
  State<ClickWheel> createState() => _ClickWheelState();
}

class _ClickWheelState extends State<ClickWheel> {
  double? _lastAngle;
  var _accumulated = 0.0;
  WheelButton? _pressed;
  DateTime _lastTick = DateTime.now();

  double get _radius => widget.size / 2;

  double get _centerRadius => widget.size * 0.19;

  Offset _fromCenter(Offset local) => local - Offset(_radius, _radius);

  double _angleOf(Offset local) {
    final v = _fromCenter(local);
    return math.atan2(v.dy, v.dx);
  }

  bool _onRing(Offset local) {
    final distance = _fromCenter(local).distance;
    return distance > _centerRadius && distance <= _radius;
  }

  WheelButton? _buttonAt(Offset local) {
    final distance = _fromCenter(local).distance;
    if (distance > _radius) return null;
    if (distance <= _centerRadius) return WheelButton.select;
    // 0 is to the right, angles grow clockwise in screen coordinates.
    final angle = _angleOf(local);
    const quarter = math.pi / 4;
    if (angle > -quarter && angle <= quarter) return WheelButton.next;
    if (angle > quarter && angle <= 3 * quarter) return WheelButton.playPause;
    if (angle > -3 * quarter && angle <= -quarter) return WheelButton.menu;
    return WheelButton.previous;
  }

  Offset? _downAt;
  var _scrolled = false;

  void _onPointerDown(PointerDownEvent event) {
    final local = event.localPosition;
    _downAt = local;
    _scrolled = false;
    _accumulated = 0;
    _lastAngle = _onRing(local) ? _angleOf(local) : null;
    setState(() => _pressed = _buttonAt(local));
  }

  void _onPointerMove(PointerMoveEvent event) {
    final local = event.localPosition;
    final last = _lastAngle;
    if (last == null) return;
    // Keep tracking even if the finger drifts a little off the ring.
    if (_fromCenter(local).distance < _centerRadius * 0.5) return;
    final angle = _angleOf(local);
    var delta = angle - last;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastAngle = angle;
    _accumulated += delta;

    while (_accumulated.abs() >= ClickWheel.tickAngle) {
      if (!_scrolled) {
        _scrolled = true;
        setState(() => _pressed = null);
      }
      final step = _accumulated > 0 ? 1 : -1;
      _accumulated -= step * ClickWheel.tickAngle;
      final now = DateTime.now();
      // Spinning fast moves further, like the real wheel's acceleration.
      final fast = now.difference(_lastTick).inMilliseconds < 35;
      _lastTick = now;
      if (widget.haptics) HapticFeedback.selectionClick().ignore();
      widget.onScroll(fast ? step * 2 : step);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    _lastAngle = null;
    final button = _pressed;
    setState(() => _pressed = null);
    if (_scrolled || down == null || button == null) return;
    if ((event.localPosition - down).distance > widget.size * 0.08) return;
    if (widget.haptics) HapticFeedback.lightImpact().ignore();
    widget.onButton(button);
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _downAt = null;
    _lastAngle = null;
    setState(() => _pressed = null);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final ring = dark ? const Color(0xFF2B2B2D) : Colors.white;
    final label = dark ? const Color(0xFFB9B9BE) : const Color(0xFFA4A4A8);
    final size = widget.size;
    final glyph = size * 0.055;

    Widget pressable(WheelButton button, Widget child) => AnimatedOpacity(
      duration: const Duration(milliseconds: 80),
      opacity: _pressed == button ? 0.45 : 1,
      child: child,
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ring,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.5 : 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: SizedBox.square(dimension: size),
            ),
            Positioned(
              top: size * 0.07,
              child: pressable(
                WheelButton.menu,
                Text(
                  'MENU',
                  style: TextStyle(
                    color: label,
                    fontSize: size * 0.068,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            Positioned(
              left: size * 0.06,
              child: pressable(
                WheelButton.previous,
                _SkipGlyph(size: glyph * 1.5, color: label, forward: false),
              ),
            ),
            Positioned(
              right: size * 0.06,
              child: pressable(
                WheelButton.next,
                _SkipGlyph(size: glyph * 1.5, color: label, forward: true),
              ),
            ),
            Positioned(
              bottom: size * 0.07,
              child: pressable(
                WheelButton.playPause,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow, size: glyph * 1.3, color: label),
                    Icon(Icons.pause, size: glyph * 1.2, color: label),
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: _centerRadius * 2,
              height: _centerRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? _pressed == WheelButton.select
                            ? const [Color(0xFF151516), Color(0xFF222224)]
                            : const [Color(0xFF3A3A3D), Color(0xFF1C1C1E)]
                      : _pressed == WheelButton.select
                      ? const [Color(0xFFC9C9CC), Color(0xFFDDDDE0)]
                      : const [Color(0xFFDADADD), Color(0xFFF2F2F4)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.4 : 0.06),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar-and-double-triangle skip glyph printed on the click wheel.
class _SkipGlyph extends StatelessWidget {
  const _SkipGlyph({
    required this.size,
    required this.color,
    required this.forward,
  });

  final double size;
  final Color color;
  final bool forward;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 1.3, size * 0.6),
    painter: _SkipPainter(color: color, forward: forward),
  );
}

class _SkipPainter extends CustomPainter {
  const _SkipPainter({required this.color, required this.forward});

  final Color color;
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    if (!forward) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final paint = Paint()..color = color;
    final h = size.height;
    final bar = h * 0.22;
    final tri = (size.width - bar) / 2;
    for (var i = 0; i < 2; i++) {
      final x = i * tri;
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + tri, h / 2)
          ..lineTo(x, h)
          ..close(),
        paint,
      );
    }
    canvas.drawRect(Rect.fromLTWH(size.width - bar, 0, bar, h), paint);
  }

  @override
  bool shouldRepaint(_SkipPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.forward != forward;
}
