import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets.dart';

// The picture is a circle. Distances are measured from the pitch in the middle
// and written as a share (0 to 1) of the radius.
//
//   0.06 - 0.66   inside the field   -> 1, 2 or 3 runs
//   0.66 - 0.82   boundary rope area -> 4 runs
//   0.82 - 1.00   over the rope      -> 6 runs

/// Where the boundary rope is drawn.
const double kBoundaryRadius = 0.74;

/// Start of the "four" ring (end of the field for 1, 2 and 3 runs).
const double kFourInner = 0.66;

/// End of the "four" ring (start of the "six" ring).
const double kFourOuter = 0.82;

/// Where a six is drawn after it is placed.
const double _sixRadius = 0.92;

/// Allowed distances (inner to outer) for a number of runs.
class _Zone {
  const _Zone(this.inner, this.outer);

  final double inner;
  final double outer;
}

_Zone _zoneFor(int runs) {
  if (runs >= 6) return const _Zone(kFourOuter, 1.0);
  if (runs >= 4) return const _Zone(kFourInner, kFourOuter);
  return const _Zone(0.06, kFourInner);
}

/// One scoring shot: where it went and how many runs it was worth.
/// x and y are measured from the pitch in the middle: (0, 0) is the pitch and
/// the edge of the picture is at distance 1.
class WagonShot {
  const WagonShot(this.x, this.y, this.runs);

  final double x;
  final double y;
  final int runs;
}

/// Result of checking a position against the runs scored.
class ShotCheck {
  const ShotCheck(this.point, [this.error]);

  /// The position to store (snapped onto the rope ring for fours and sixes).
  final Offset point;

  /// Null when the position is fine for these runs.
  final String? error;
}

/// Checks a position against the runs: 1, 2 or 3 stay inside the field, a four
/// is at the rope, a six is over the rope.
ShotCheck checkShot(int runs, Offset p) {
  final dist = p.distance;
  final zone = _zoneFor(runs);
  if (dist < 0.06) {
    return ShotCheck(p, 'The ball cannot stop on the pitch in the middle.');
  }
  if (dist < zone.inner || dist > zone.outer) {
    return ShotCheck(p, 'The ball cannot go here for $runs runs.');
  }
  final unit = p / dist;
  if (runs >= 6) return ShotCheck(unit * _sixRadius);
  if (runs >= 4) return ShotCheck(unit * kBoundaryRadius);
  return ShotCheck(p);
}

Color shotColor(int runs) => runs >= 6
    ? const Color(0xFFFF7043)
    : (runs >= 4 ? const Color(0xFFFFEE58) : const Color(0xFF81D4FA));

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

void _paintField(Canvas canvas, Offset c, double r) {
  // outside the rope
  canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1B5E20));
  // playing field
  final field = Rect.fromCircle(center: c, radius: r * kBoundaryRadius);
  canvas.drawCircle(
    c,
    r * kBoundaryRadius,
    Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
      ).createShader(field),
  );
  // faint spokes
  final spoke = Paint()
    ..color = const Color(0x22FFFFFF)
    ..strokeWidth = 1;
  for (var k = 0; k < 8; k++) {
    final a = k * math.pi / 4;
    canvas.drawLine(
      c,
      c + Offset(math.cos(a), math.sin(a)) * (r * kBoundaryRadius),
      spoke,
    );
  }
  // inner circle
  canvas.drawCircle(
    c,
    r * 0.38,
    Paint()
      ..color = const Color(0x44FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  // boundary rope
  canvas.drawCircle(
    c,
    r * kBoundaryRadius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  // pitch
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: r * 0.10, height: r * 0.30),
      Radius.circular(r * 0.02),
    ),
    Paint()..color = const Color(0xFFD9B77E),
  );
}

void _drawLabel(
    Canvas canvas, String text, Offset center, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Greys out the areas that cannot be used for these runs and labels the
/// three areas.
void _paintZones(Canvas canvas, Offset c, double r, int runs) {
  final gray = Paint()..color = const Color(0xCC9E9E9E);
  void ring(double inner, double outer) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: c, radius: r * outer));
    if (inner > 0) {
      path.addOval(Rect.fromCircle(center: c, radius: r * inner));
    }
    canvas.drawPath(path, gray);
  }

  final single = runs < 4;
  final four = runs >= 4 && runs < 6;
  final six = runs >= 6;
  if (!single) ring(0, kFourInner);
  if (!four) ring(kFourInner, kFourOuter);
  if (!six) ring(kFourOuter, 1.0);

  Color label(bool active) => active ? Colors.white : Colors.white70;
  _drawLabel(canvas, '1  2  3', c + Offset(0, r * 0.42), r * 0.075, label(single));
  _drawLabel(canvas, '4', c + Offset(0, -r * kBoundaryRadius), r * 0.085, label(four));
  _drawLabel(canvas, '6', c + Offset(0, -r * 0.91), r * 0.085, label(six));
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.shots,
    this.marker,
    this.progress = 1.0,
    this.runs = 0,
    this.showZones = false,
  });

  final List<WagonShot> shots;

  /// The chosen position while a shot is being entered.
  final Offset? marker;

  /// How far the ball has travelled along the line to the marker (0 to 1).
  final double progress;
  final int runs;
  final bool showZones;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = Offset(size.width / 2, size.height / 2);
    _paintField(canvas, c, r);
    if (showZones) _paintZones(canvas, c, r, runs);

    for (final s in shots) {
      final end = c + Offset(s.x * r, s.y * r);
      canvas.drawLine(
        c,
        end,
        Paint()
          ..color = shotColor(s.runs).withAlpha(210)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(end, 3, Paint()..color = shotColor(s.runs));
    }

    final m = marker;
    if (m != null) {
      final end = c + Offset(m.dx * r, m.dy * r);
      final pos = Offset.lerp(c, end, progress)!;
      canvas.drawLine(
        c,
        pos,
        Paint()
          ..color = shotColor(runs)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      paintCricketBall(canvas, pos, r * 0.06, tilt: progress * 12);
      if (progress >= 1.0) {
        canvas.drawCircle(
          pos,
          r * 0.095,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.progress != progress ||
      old.marker != marker ||
      old.shots != shots ||
      old.runs != runs ||
      old.showZones != showZones;
}

/// A finished wagon wheel with a colour key, for the player statistics page.
class WagonWheelView extends StatelessWidget {
  const WagonWheelView({super.key, required this.shots});

  final List<WagonShot> shots;

  Widget _key(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _WheelPainter(shots: shots)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _key(context, shotColor(1), '1, 2 or 3 runs'),
            _key(context, shotColor(4), 'Four'),
            _key(context, shotColor(6), 'Six'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          shots.isEmpty
              ? 'No shot directions recorded yet. They are saved when you '
                  'place the ball on the field after a scoring shot.'
              : '${shots.length} shots plotted from the pitch in the middle.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pop-up used while scoring
// ---------------------------------------------------------------------------

class WagonResult {
  const WagonResult.shot(this.point) : skipped = false;
  const WagonResult.skip()
      : point = null,
        skipped = true;

  /// Where the ball went (null when the scorer skipped).
  final Offset? point;
  final bool skipped;
}

/// Returns the chosen position, or [WagonResult.skip] to score without one.
Future<WagonResult?> showWagonWheel(
  BuildContext context, {
  required String batterName,
  required int runs,
}) {
  return showDialog<WagonResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WagonWheelDialog(batterName: batterName, runs: runs),
  );
}

class _WagonWheelDialog extends StatefulWidget {
  const _WagonWheelDialog({required this.batterName, required this.runs});

  final String batterName;
  final int runs;

  @override
  State<_WagonWheelDialog> createState() => _WagonWheelDialogState();
}

class _WagonWheelDialogState extends State<_WagonWheelDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fly;
  Offset? _pos; // chosen position (already inside the allowed area)
  bool _dragging = false;
  bool _flying = false;
  double _side = 280;

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  String get _hint {
    if (widget.runs >= 6) {
      return 'A six goes over the rope. Touch the outer ring, drag to move it '
          'around, then press OK.';
    }
    if (widget.runs >= 4) {
      return 'A four reaches the rope. Touch the ring at the rope, drag to move '
          'it around, then press OK.';
    }
    return 'Touch the field where the ball stopped, drag to move it, then '
        'press OK.';
  }

  Offset _toUnit(Offset local) {
    final half = _side / 2;
    return Offset((local.dx - half) / half, (local.dy - half) / half);
  }

  /// Keeps the position in the allowed area. Fours and sixes slide along
  /// their ring, so the ball moves clockwise or anticlockwise.
  Offset _constrain(Offset p) {
    final zone = _zoneFor(widget.runs);
    final dist = p.distance;
    final unit = dist < 0.0001 ? const Offset(0, -1) : p / dist;
    if (widget.runs >= 6) return unit * _sixRadius;
    if (widget.runs >= 4) return unit * kBoundaryRadius;
    final d = dist < 0.12 ? 0.12 : (dist > zone.outer - 0.04 ? zone.outer - 0.04 : dist);
    return unit * d;
  }

  void _down(Offset local) {
    if (_flying) return;
    final p = _toUnit(local);
    final zone = _zoneFor(widget.runs);
    final dist = p.distance;
    // greyed-out areas do nothing
    if (dist < zone.inner || dist > zone.outer) return;
    setState(() {
      _dragging = true;
      _pos = _constrain(p);
    });
  }

  void _move(Offset local) {
    if (_flying || !_dragging) return;
    setState(() => _pos = _constrain(_toUnit(local)));
  }

  void _rotate(double degrees) {
    final p = _pos;
    if (p == null || _flying) return;
    final a = degrees * math.pi / 180;
    final cosA = math.cos(a);
    final sinA = math.sin(a);
    setState(() {
      _pos = Offset(p.dx * cosA - p.dy * sinA, p.dx * sinA + p.dy * cosA);
    });
  }

  void _confirm() {
    final p = _pos;
    if (p == null || _flying) return;
    setState(() => _flying = true);
    HapticFeedback.mediumImpact();
    _fly.forward(from: 0).whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) Navigator.pop(context, WagonResult.shot(p));
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    _side = math.min(340.0, MediaQuery.of(context).size.width - 70);
    final runsText = widget.runs == 1 ? '1 run' : '${widget.runs} runs';
    final canMove = _pos != null && !_flying;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      title: Text('${widget.batterName} scored $runsText'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Show where the ball went.', style: text.bodyMedium),
            const SizedBox(height: 2),
            Text(_hint, style: text.bodySmall),
            const SizedBox(height: 10),
            SizedBox(
              width: _side,
              height: _side,
              child: GestureDetector(
                onPanDown: (d) => _down(d.localPosition),
                onPanUpdate: (d) => _move(d.localPosition),
                onPanEnd: (_) => _dragging = false,
                onPanCancel: () => _dragging = false,
                child: AnimatedBuilder(
                  animation: _fly,
                  builder: (context, _) => CustomPaint(
                    painter: _WheelPainter(
                      shots: const <WagonShot>[],
                      marker: _pos,
                      progress:
                          _flying ? Curves.easeOut.transform(_fly.value) : 1.0,
                      runs: widget.runs,
                      showZones: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Move anticlockwise',
                  onPressed: canMove ? () => _rotate(-8) : null,
                  icon: const Icon(Icons.rotate_left),
                ),
                const SizedBox(width: 12),
                Text('Move around', style: text.bodyMedium),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: 'Move clockwise',
                  onPressed: canMove ? () => _rotate(8) : null,
                  icon: const Icon(Icons.rotate_right),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _flying
              ? null
              : () => Navigator.pop(context, const WagonResult.skip()),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: (_pos != null && !_flying) ? _confirm : null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
