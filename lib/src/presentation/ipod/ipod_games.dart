import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jplayer/src/domain/providers/providers.dart';
import 'package:jplayer/src/presentation/ipod/ipod_shell.dart';

enum _GameStatus { ready, playing, paused, over, won }

/// Shared plumbing for the click wheel games: a frame ticker, the
/// ready/paused/game over overlays and a score line. The wheel's centre
/// button starts and pauses; MENU goes back.
abstract class _GameState<T extends ConsumerStatefulWidget>
    extends IpodScreenState<T>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  var status = _GameStatus.ready;
  var score = 0;

  /// The play field in logical pixels, set on layout.
  Size field = Size.zero;

  String get name;

  String get hint;

  void reset();

  void update(double dt);

  void paintGame(Canvas canvas, Size size);

  void scroll(int step);

  bool get haptics => ref.read(settingProvider(AppSetting.ipodHaptics));

  void bump() {
    if (haptics) HapticFeedback.lightImpact().ignore();
  }

  void end({bool won = false}) {
    if (haptics) HapticFeedback.heavyImpact().ignore();
    setState(() => status = won ? _GameStatus.won : _GameStatus.over);
    _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _last = elapsed;
    if (status != _GameStatus.playing || field.isEmpty) return;
    setState(() => update(dt));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void onScroll(int step) {
    if (status == _GameStatus.playing) scroll(step);
  }

  @override
  void onSelect() {
    switch (status) {
      case _GameStatus.ready || _GameStatus.over || _GameStatus.won:
        setState(() {
          score = 0;
          reset();
          status = _GameStatus.playing;
        });
        _last = Duration.zero;
        if (_ticker.isActive) _ticker.stop();
        _ticker.start();
      case _GameStatus.playing:
        setState(() => status = _GameStatus.paused);
      case _GameStatus.paused:
        setState(() => status = _GameStatus.playing);
    }
  }

  @override
  bool onPlayPause() {
    if (status == _GameStatus.playing || status == _GameStatus.paused) {
      onSelect();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight - 18);
      if (size != field) {
        final first = field.isEmpty;
        field = size;
        if (first) reset();
      }
      return Column(
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            color: const Color(0xFFF2F2F4),
            child: Row(
              children: [
                Text(
                  'Score: $score',
                  style: ipodTextStyle.copyWith(fontSize: 12),
                ),
                const Spacer(),
                if (status == _GameStatus.playing)
                  Text(
                    'Select to pause',
                    style: ipodTextStyle.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF888888),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _GamePainter(this)),
                if (status != _GameStatus.playing) _overlay(),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _overlay() {
    final (title, subtitle) = switch (status) {
      _GameStatus.ready => (name, hint),
      _GameStatus.paused => ('Paused', 'Press the centre button to resume'),
      _GameStatus.over => ('Game Over', 'Score $score • centre to play again'),
      _GameStatus.won => ('You Win!', 'Score $score • centre to play again'),
      _GameStatus.playing => ('', ''),
    };
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.78),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: ipodTextStyle.copyWith(fontSize: 20)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: ipodTextStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF555555),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter(this.game);

  final _GameState game;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE9EAEE)],
        ).createShader(Offset.zero & size),
    );
    game.paintGame(canvas, size);
  }

  @override
  bool shouldRepaint(_GamePainter oldDelegate) => true;
}

final _ink = Paint()..color = const Color(0xFF2B2B2E);
final _blue = Paint()
  ..shader = null
  ..color = const Color(0xFF2F74D0);

// ---------------------------------------------------------------- Brick --

class BreakoutGame extends ConsumerStatefulWidget {
  const BreakoutGame({super.key});

  @override
  ConsumerState<BreakoutGame> createState() => _BreakoutState();
}

class _BreakoutState extends _GameState<BreakoutGame> {
  static const _rows = 5;
  static const _cols = 8;
  static const _colors = [
    Color(0xFFE5483B),
    Color(0xFFF29A38),
    Color(0xFFF2D13A),
    Color(0xFF5CC14E),
    Color(0xFF3F8EE6),
  ];

  late List<bool> _bricks;
  var _paddle = 0.5;
  var _ball = Offset.zero;
  var _velocity = Offset.zero;
  var _lives = 3;

  double get _paddleWidth => field.width * 0.22;

  double get _ballRadius => field.width * 0.016;

  @override
  String get name => 'Brick';

  @override
  String get hint =>
      'Turn the wheel to move the paddle.\nPress the centre to start.';

  @override
  void reset() {
    _bricks = List.filled(_rows * _cols, true);
    _lives = 3;
    _serve();
  }

  void _serve() {
    _paddle = 0.5;
    _ball = Offset(field.width / 2, field.height * 0.7);
    final speed = field.height * 0.75;
    _velocity = Offset(
      speed * 0.55 * (math.Random().nextBool() ? 1 : -1),
      -speed,
    );
  }

  Rect _brickRect(int index) {
    final gap = 3.0;
    final width = (field.width - gap * (_cols + 1)) / _cols;
    final height = field.height * 0.05;
    final row = index ~/ _cols;
    final col = index % _cols;
    return Rect.fromLTWH(
      gap + col * (width + gap),
      field.height * 0.08 + row * (height + gap),
      width,
      height,
    );
  }

  Rect get _paddleRect => Rect.fromCenter(
    center: Offset(field.width * _paddle, field.height - 10),
    width: _paddleWidth,
    height: 6,
  );

  @override
  void scroll(int step) {
    final half = _paddleWidth / 2 / field.width;
    _paddle = (_paddle + step * 0.035).clamp(half, 1 - half);
  }

  @override
  void update(double dt) {
    var next = _ball + _velocity * dt;
    final r = _ballRadius;
    if (next.dx < r || next.dx > field.width - r) {
      _velocity = Offset(-_velocity.dx, _velocity.dy);
      next = Offset(next.dx.clamp(r, field.width - r), next.dy);
    }
    if (next.dy < r) {
      _velocity = Offset(_velocity.dx, _velocity.dy.abs());
    }
    final paddle = _paddleRect;
    if (_velocity.dy > 0 &&
        next.dy + r >= paddle.top &&
        next.dy - r <= paddle.bottom &&
        next.dx >= paddle.left - r &&
        next.dx <= paddle.right + r) {
      // Where the ball lands on the paddle steers it, like the original.
      final hit = ((next.dx - paddle.center.dx) / (paddle.width / 2)).clamp(
        -1.0,
        1.0,
      );
      final speed = _velocity.distance * 1.02;
      final angle = hit * math.pi / 3;
      _velocity = Offset(speed * math.sin(angle), -speed * math.cos(angle));
      bump();
    }
    for (var i = 0; i < _bricks.length; i++) {
      if (!_bricks[i]) continue;
      final brick = _brickRect(i);
      if (brick.inflate(r).contains(next)) {
        _bricks[i] = false;
        score += 10 * (_rows - i ~/ _cols);
        final fromSide = _ball.dx < brick.left || _ball.dx > brick.right;
        _velocity = fromSide
            ? Offset(-_velocity.dx, _velocity.dy)
            : Offset(_velocity.dx, -_velocity.dy);
        bump();
        break;
      }
    }
    _ball = next;
    if (_ball.dy > field.height + r) {
      _lives--;
      if (_lives <= 0) {
        end();
      } else {
        bump();
        _serve();
      }
    }
    if (!_bricks.contains(true)) end(won: true);
  }

  @override
  void paintGame(Canvas canvas, Size size) {
    for (var i = 0; i < _bricks.length; i++) {
      if (!_bricks[i]) continue;
      final rect = _brickRect(i);
      final color = _colors[i ~/ _cols];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(color, Colors.white, 0.35)!, color],
          ).createShader(rect),
      );
    }
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(_paddleRect, const Radius.circular(3)),
        _ink,
      )
      ..drawCircle(_ball, _ballRadius, _blue);
    for (var i = 0; i < _lives; i++) {
      canvas.drawCircle(
        Offset(size.width - 8 - i * 10, 8),
        3,
        Paint()..color = const Color(0xFFAAAAAA),
      );
    }
  }
}

// ----------------------------------------------------------------- Pong --

class PongGame extends ConsumerStatefulWidget {
  const PongGame({super.key});

  @override
  ConsumerState<PongGame> createState() => _PongState();
}

class _PongState extends _GameState<PongGame> {
  var _player = 0.5;
  var _cpu = 0.5;
  var _ball = Offset.zero;
  var _velocity = Offset.zero;
  var _cpuScore = 0;
  static const _winningScore = 7;

  double get _paddleHeight => field.height * 0.26;

  double get _ballSize => field.width * 0.025;

  @override
  String get name => 'Pong';

  @override
  String get hint =>
      'Turn the wheel to move your paddle. First to $_winningScore wins.\n'
      'Press the centre to start.';

  @override
  void reset() {
    _cpuScore = 0;
    _player = 0.5;
    _cpu = 0.5;
    _serve(towardsPlayer: true);
  }

  void _serve({required bool towardsPlayer}) {
    _ball = Offset(field.width / 2, field.height / 2);
    final speed = field.width * 0.6;
    final angle = (math.Random().nextDouble() - 0.5) * math.pi / 3;
    _velocity = Offset(
      speed * math.cos(angle) * (towardsPlayer ? -1 : 1),
      speed * math.sin(angle),
    );
  }

  @override
  void scroll(int step) {
    final half = _paddleHeight / 2 / field.height;
    _player = (_player + step * 0.04).clamp(half, 1 - half);
  }

  Rect _paddle(double center, {required bool left}) => Rect.fromCenter(
    center: Offset(left ? 8 : field.width - 8, field.height * center),
    width: 5,
    height: _paddleHeight,
  );

  @override
  void update(double dt) {
    // The computer tracks the ball, a little slower than it could.
    final target = _ball.dy / field.height;
    final half = _paddleHeight / 2 / field.height;
    final maxMove = 0.9 * dt;
    _cpu = (_cpu + (target - _cpu).clamp(-maxMove, maxMove)).clamp(
      half,
      1 - half,
    );

    var next = _ball + _velocity * dt;
    final s = _ballSize / 2;
    if (next.dy < s || next.dy > field.height - s) {
      _velocity = Offset(_velocity.dx, -_velocity.dy);
      next = Offset(next.dx, next.dy.clamp(s, field.height - s));
    }
    for (final left in [true, false]) {
      final paddle = _paddle(left ? _player : _cpu, left: left);
      final moving = left ? _velocity.dx < 0 : _velocity.dx > 0;
      if (moving && paddle.inflate(s).contains(next)) {
        final hit = ((next.dy - paddle.center.dy) / (paddle.height / 2)).clamp(
          -1.0,
          1.0,
        );
        final speed = math.min(_velocity.distance * 1.06, field.width * 1.6);
        final angle = hit * math.pi / 3.2;
        _velocity = Offset(
          speed * math.cos(angle) * (left ? 1 : -1),
          speed * math.sin(angle),
        );
        if (left) bump();
      }
    }
    _ball = next;
    if (_ball.dx < -s) {
      _cpuScore++;
      bump();
      if (_cpuScore >= _winningScore) return end();
      _serve(towardsPlayer: false);
    } else if (_ball.dx > field.width + s) {
      score++;
      bump();
      if (score >= _winningScore) return end(won: true);
      _serve(towardsPlayer: true);
    }
  }

  @override
  void paintGame(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = const Color(0xFFBBBBBB)
      ..strokeWidth = 2;
    for (var y = 0.0; y < size.height; y += 10) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + 5),
        dash,
      );
    }
    final scoreStyle = ipodTextStyle.copyWith(
      fontSize: 22,
      color: const Color(0xFFBBBBBB),
    );
    for (final (value, x) in [(score, 0.38), (_cpuScore, 0.62)]) {
      final painter = TextPainter(
        text: TextSpan(text: '$value', style: scoreStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter
        ..paint(canvas, Offset(size.width * x - painter.width / 2, 4))
        ..dispose();
    }
    canvas
      ..drawRect(_paddle(_player, left: true), _blue)
      ..drawRect(_paddle(_cpu, left: false), _ink)
      ..drawRect(
        Rect.fromCenter(center: _ball, width: _ballSize, height: _ballSize),
        _ink,
      );
  }
}

// ---------------------------------------------------------------- Snake --

class SnakeGame extends ConsumerStatefulWidget {
  const SnakeGame({super.key});

  @override
  ConsumerState<SnakeGame> createState() => _SnakeState();
}

class _SnakeState extends _GameState<SnakeGame> {
  static const _columns = 24;
  static const _directions = [
    math.Point(1, 0),
    math.Point(0, 1),
    math.Point(-1, 0),
    math.Point(0, -1),
  ];

  final _random = math.Random();
  var _body = <math.Point<int>>[];
  var _heading = 0;
  var _pendingTurn = 0;
  var _food = const math.Point(0, 0);
  var _sinceStep = 0.0;

  int get _rows =>
      math.max(8, (field.height / (field.width / _columns)).floor());

  double get _cell => field.width / _columns;

  @override
  String get name => 'Snake';

  @override
  String get hint =>
      'Turn the wheel clockwise to turn right, anticlockwise to turn left.\n'
      'Press the centre to start.';

  @override
  void reset() {
    final mid = math.Point(_columns ~/ 2, _rows ~/ 2);
    _body = [for (var i = 0; i < 4; i++) math.Point(mid.x - i, mid.y)];
    _heading = 0;
    _pendingTurn = 0;
    _sinceStep = 0;
    _placeFood();
  }

  void _placeFood() {
    while (true) {
      final food = math.Point(
        _random.nextInt(_columns),
        _random.nextInt(_rows),
      );
      if (!_body.contains(food)) {
        _food = food;
        return;
      }
    }
  }

  @override
  void scroll(int step) {
    // One turn per wheel click, queued until the next move.
    _pendingTurn = step.sign;
  }

  @override
  void update(double dt) {
    _sinceStep += dt;
    final interval = math.max(0.06, 0.16 - _body.length * 0.002);
    if (_sinceStep < interval) return;
    _sinceStep = 0;
    if (_pendingTurn != 0) {
      _heading = (_heading + _pendingTurn) % 4;
      _pendingTurn = 0;
    }
    final direction = _directions[_heading];
    final head = _body.first;
    final next = math.Point(head.x + direction.x, head.y + direction.y);
    if (next.x < 0 ||
        next.y < 0 ||
        next.x >= _columns ||
        next.y >= _rows ||
        _body.sublist(0, _body.length - 1).contains(next)) {
      return end();
    }
    _body.insert(0, next);
    if (next == _food) {
      score += 1;
      bump();
      _placeFood();
    } else {
      _body.removeLast();
    }
  }

  @override
  void paintGame(Canvas canvas, Size size) {
    final cell = _cell;
    final top = (size.height - _rows * cell) / 2;
    canvas.drawRect(
      Rect.fromLTWH(0, top, _columns * cell, _rows * cell),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFCCCCCC),
    );
    Rect cellRect(math.Point<int> p) =>
        Rect.fromLTWH(p.x * cell, top + p.y * cell, cell, cell).deflate(1);
    canvas.drawOval(cellRect(_food), Paint()..color = const Color(0xFFE5483B));
    for (final (index, part) in _body.indexed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect(part), Radius.circular(cell * 0.25)),
        index == 0 ? _blue : _ink,
      );
    }
  }
}
