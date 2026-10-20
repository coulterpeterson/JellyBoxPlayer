import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jplayer/src/presentation/ipod/click_wheel.dart';

/// The Sansa e200's controls: a glowing blue scroll ring around a centre
/// select button, four arc buttons around the ring (play/pause, previous,
/// next, submenu) and the power/menu button. Spinning the ring emits
/// [onScroll] ticks with a light haptic click, like the click wheel.
class SansaControls extends StatefulWidget {
  const SansaControls({
    required this.size,
    required this.onScroll,
    required this.onButton,
    this.haptics = true,
    super.key,
  });

  final double size;
  final ValueChanged<int> onScroll;
  final ValueChanged<WheelButton> onButton;
  final bool haptics;

  @override
  State<SansaControls> createState() => _SansaControlsState();
}

class _SansaControlsState extends State<SansaControls> {
  double? _lastAngle;
  var _accumulated = 0.0;
  var _scrolled = false;
  var _touchingRing = false;
  Offset? _downAt;
  WheelButton? _pressed;
  DateTime _lastTick = DateTime.now();

  double get _r => widget.size / 2;
  double get _centerR => widget.size * 0.21;
  double get _ringR => widget.size * 0.31;

  Offset _fromCenter(Offset local) => local - Offset(_r, _r);

  double _angleOf(Offset local) {
    final v = _fromCenter(local);
    return math.atan2(v.dy, v.dx);
  }

  WheelButton? _buttonAt(Offset local) {
    final distance = _fromCenter(local).distance;
    if (distance > _r) return null;
    if (distance <= _centerR) return WheelButton.select;
    if (distance <= _ringR) return null;
    final angle = _angleOf(local);
    const quarter = math.pi / 4;
    if (angle > -quarter && angle <= quarter) return WheelButton.next;
    if (angle > quarter && angle <= 3 * quarter) return WheelButton.options;
    if (angle > -3 * quarter && angle <= -quarter) {
      return WheelButton.playPause;
    }
    return WheelButton.previous;
  }

  void _down(PointerDownEvent event) {
    final local = event.localPosition;
    final distance = _fromCenter(local).distance;
    _downAt = local;
    _scrolled = false;
    _accumulated = 0;
    final onRing = distance > _centerR && distance <= _ringR + _r * 0.04;
    _lastAngle = onRing ? _angleOf(local) : null;
    setState(() {
      _touchingRing = onRing;
      _pressed = _buttonAt(local);
    });
  }

  void _move(PointerMoveEvent event) {
    final last = _lastAngle;
    if (last == null) return;
    final local = event.localPosition;
    if (_fromCenter(local).distance < _centerR * 0.5) return;
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
      final fast = now.difference(_lastTick).inMilliseconds < 35;
      _lastTick = now;
      if (widget.haptics) HapticFeedback.selectionClick().ignore();
      widget.onScroll(fast ? step * 2 : step);
    }
  }

  void _up(PointerUpEvent event) {
    final down = _downAt;
    final button = _pressed;
    _downAt = null;
    _lastAngle = null;
    setState(() {
      _pressed = null;
      _touchingRing = false;
    });
    if (_scrolled || down == null || button == null) return;
    if ((event.localPosition - down).distance > widget.size * 0.08) return;
    if (widget.haptics) HapticFeedback.lightImpact().ignore();
    widget.onButton(button);
  }

  void _cancel(PointerCancelEvent _) => setState(() {
    _downAt = null;
    _lastAngle = null;
    _pressed = null;
    _touchingRing = false;
  });

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _cancel,
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _SansaPainter(
        pressed: _pressed,
        glowing: _touchingRing,
      ),
    ),
  );
}

class _SansaPainter extends CustomPainter {
  const _SansaPainter({required this.pressed, required this.glowing});

  final WheelButton? pressed;
  final bool glowing;

  static const _label = Color(0xFFD6D7DC);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringOuter = r * 0.62;
    final ringInner = r * 0.44;
    final buttonsInner = r * 0.66;

    // Arc buttons around the ring, with small gaps between them.
    const gap = 0.05;
    final buttons = [
      (WheelButton.playPause, -math.pi / 2),
      (WheelButton.next, 0.0),
      (WheelButton.options, math.pi / 2),
      (WheelButton.previous, math.pi),
    ];
    for (final (button, mid) in buttons) {
      final start = mid - math.pi / 4 + gap;
      const sweep = math.pi / 2 - 2 * gap;
      final path = Path()
        ..arcTo(Rect.fromCircle(center: c, radius: r), start, sweep, true)
        ..arcTo(
          Rect.fromCircle(center: c, radius: buttonsInner),
          start + sweep,
          -sweep,
          false,
        )
        ..close();
      final down = pressed == button;
      canvas
        ..drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: down
                  ? const [Color(0xFF3A3B40), Color(0xFF26272B)]
                  : const [Color(0xFF2B2C30), Color(0xFF0E0E10)],
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF55565C).withValues(alpha: 0.7),
        );
      final glyphCenter =
          c + Offset(math.cos(mid), math.sin(mid)) * ((r + buttonsInner) / 2);
      _glyph(canvas, button, glyphCenter, r * 0.085);
    }

    // The scroll ring: a blue glow, brighter while touched.
    final glow = glowing ? 1.0 : 0.75;
    canvas.drawCircle(
      c,
      (ringOuter + ringInner) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringOuter - ringInner
        ..color = const Color(0xFF2F6BFF).withValues(alpha: 0.55 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
    canvas.drawCircle(
      c,
      (ringOuter + ringInner) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringOuter - ringInner
        ..shader = SweepGradient(
          colors: glowing
              ? const [
                  Color(0xFF9FE4FF),
                  Color(0xFF4FA6FF),
                  Color(0xFF9FE4FF),
                  Color(0xFF4FA6FF),
                  Color(0xFF9FE4FF),
                ]
              : const [
                  Color(0xFF4E86FF),
                  Color(0xFF2350E0),
                  Color(0xFF4E86FF),
                  Color(0xFF2350E0),
                  Color(0xFF4E86FF),
                ],
        ).createShader(Rect.fromCircle(center: c, radius: ringOuter)),
    );
    // Fine ridges on the ring.
    final ridge = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i < 72; i++) {
      final a = i * math.pi * 2 / 72;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * (ringInner + 2),
        c + dir * (ringOuter - 2),
        ridge,
      );
    }

    // The centre button.
    final centerR = ringInner - r * 0.02;
    final centerDown = pressed == WheelButton.select;
    canvas
      ..drawCircle(
        c,
        centerR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 1.1,
            colors: centerDown
                ? const [Color(0xFF2A2B30), Color(0xFF0A0A0C)]
                : const [Color(0xFF3B3C42), Color(0xFF060607)],
          ).createShader(Rect.fromCircle(center: c, radius: centerR)),
      )
      ..drawCircle(
        c,
        centerR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black,
      );
  }

  void _glyph(Canvas canvas, WheelButton button, Offset at, double s) {
    final paint = Paint()..color = _label;
    Path triangle(double x, double y, double w, {required bool right}) => Path()
      ..moveTo(right ? x : x + w, y - w * 0.6)
      ..lineTo(right ? x + w : x, y)
      ..lineTo(right ? x : x + w, y + w * 0.6)
      ..close();
    switch (button) {
      case WheelButton.playPause:
        canvas
          ..drawPath(triangle(at.dx - s, at.dy, s * 0.9, right: true), paint)
          ..drawRect(
            Rect.fromLTWH(
              at.dx + s * 0.15,
              at.dy - s * 0.55,
              s * 0.22,
              s * 1.1,
            ),
            paint,
          )
          ..drawRect(
            Rect.fromLTWH(at.dx + s * 0.5, at.dy - s * 0.55, s * 0.22, s * 1.1),
            paint,
          );
      case WheelButton.previous:
        canvas
          ..drawRect(
            Rect.fromLTWH(at.dx - s * 1.1, at.dy - s * 0.55, s * 0.2, s * 1.1),
            paint,
          )
          ..drawPath(
            triangle(at.dx - s * 0.85, at.dy, s * 0.8, right: false),
            paint,
          )
          ..drawPath(
            triangle(at.dx - s * 0.05, at.dy, s * 0.8, right: false),
            paint,
          );
      case WheelButton.next:
        canvas
          ..drawPath(
            triangle(at.dx - s * 0.75, at.dy, s * 0.8, right: true),
            paint,
          )
          ..drawPath(
            triangle(at.dx + s * 0.05, at.dy, s * 0.8, right: true),
            paint,
          )
          ..drawRect(
            Rect.fromLTWH(at.dx + s * 0.9, at.dy - s * 0.55, s * 0.2, s * 1.1),
            paint,
          );
      case WheelButton.options:
        for (var i = 0; i < 3; i++) {
          final width = s * (1.8 - i * 0.35);
          canvas.drawRect(
            Rect.fromLTWH(
              at.dx + s * 0.9 - width,
              at.dy - s * 0.55 + i * s * 0.45,
              width,
              s * 0.22,
            ),
            paint,
          );
        }
      case WheelButton.menu || WheelButton.select || WheelButton.home:
        break;
    }
  }

  @override
  bool shouldRepaint(_SansaPainter oldDelegate) =>
      oldDelegate.pressed != pressed || oldDelegate.glowing != glowing;
}

/// The round power button with "menu" printed under it.
class SansaMenuButton extends StatefulWidget {
  const SansaMenuButton({
    required this.size,
    required this.onPressed,
    this.haptics = true,
    super.key,
  });

  final double size;
  final VoidCallback onPressed;
  final bool haptics;

  @override
  State<SansaMenuButton> createState() => _SansaMenuButtonState();
}

class _SansaMenuButtonState extends State<SansaMenuButton> {
  var _down = false;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _down = true),
    onPointerCancel: (_) => setState(() => _down = false),
    onPointerUp: (_) {
      setState(() => _down = false);
      if (widget.haptics) HapticFeedback.lightImpact().ignore();
      widget.onPressed();
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.4),
              colors: _down
                  ? const [Color(0xFF2E2F34), Color(0xFF111113)]
                  : const [Color(0xFF3A3B41), Color(0xFF0B0B0D)],
            ),
            border: Border.all(color: const Color(0xFF55565C)),
          ),
          child: Icon(
            Icons.power_settings_new,
            size: widget.size * 0.5,
            color: const Color(0xFFD6D7DC),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'menu',
          style: TextStyle(
            fontSize: widget.size * 0.32,
            color: const Color(0xFFD6D7DC),
            fontFamily: 'Arial',
          ),
        ),
      ],
    ),
  );
}
