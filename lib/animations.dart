import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'widgets.dart';

double _clamp01(double v) => v < 0 ? 0.0 : (v > 1 ? 1.0 : v);

Color _c(int r, int g, int b, double opacity) =>
    Color.fromRGBO(r, g, b, _clamp01(opacity));

/// Leather cricket ball (same look as the ball icon).
void _drawBall(Canvas canvas, Offset center, double radius, double spin,
    double alpha) {
  paintCricketBall(canvas, center, radius, tilt: 0.55 + spin, alpha: alpha);
}

// ===========================================================================
// WICKET ANIMATIONS - one scene for each kind of dismissal
//   bowled / hit wicket : ball hits the stumps, stumps cartwheel, bails fly
//   stumped / run out   : stumps stay up, only the bails are knocked off
//   caught              : ball flies high and drops into cupped hands
//   lbw                 : ball hits the pad, ball-tracking line, umpire's finger
// ===========================================================================

int _durationMs(WicketType? type) {
  switch (type) {
    case WicketType.caught:
      return 2800;
    case WicketType.lbw:
      return 3000;
    default:
      return 2300;
  }
}

/// When (0..1) the big title pops in.
double _textStart(WicketType? type) {
  switch (type) {
    case WicketType.caught:
      return 0.60;
    case WicketType.lbw:
      return 0.62;
    default:
      return 0.30;
  }
}

String _title(WicketType? type) => switch (type) {
      WicketType.bowled => 'BOWLED!',
      WicketType.caught => 'CAUGHT!',
      WicketType.lbw => 'LEG BEFORE WICKET!',
      WicketType.stumped => 'STUMPED!',
      WicketType.runOut => 'RUN OUT!',
      WicketType.hitWicket => 'HIT WICKET!',
      null => 'WICKET!',
    };

CustomPainter _painterFor(WicketType? type, double t) {
  switch (type) {
    case WicketType.caught:
      return _CaughtPainter(t);
    case WicketType.lbw:
      return _LbwPainter(t);
    case WicketType.stumped:
    case WicketType.runOut:
      return _WicketPainter(t, shatter: false);
    default:
      return _WicketPainter(t, shatter: true);
  }
}

/// Plays the dismissal animation on top of the whole app.
/// Completes when it has finished. Touches are blocked while it plays.
Future<void> playWicketAnimation(
  BuildContext context, {
  String? subtitle,
  WicketType? type,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<void>.value();
  final completer = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _WicketOverlay(
      subtitle: subtitle,
      type: type,
      onDone: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  overlay.insert(entry);
  HapticFeedback.heavyImpact();
  return completer.future;
}

class _WicketOverlay extends StatefulWidget {
  const _WicketOverlay({required this.onDone, this.subtitle, this.type});

  final VoidCallback onDone;
  final String? subtitle;
  final WicketType? type;

  @override
  State<_WicketOverlay> createState() => _WicketOverlayState();
}

class _WicketOverlayState extends State<_WicketOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs(widget.type)),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = _textStart(widget.type);
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          final backdrop = t < 0.08
              ? t / 0.08
              : (t > 0.90 ? (1 - t) / 0.10 : 1.0);
          final textIn =
              Curves.elasticOut.transform(_clamp01((t - start) / 0.30));
          final textOpacity = _clamp01((t - start) / 0.06) *
              (1 - _clamp01((t - 0.86) / 0.12));
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: _c(5, 18, 11, _clamp01(backdrop) * 0.88)),
              CustomPaint(painter: _painterFor(widget.type, t)),
              Align(
                alignment: const Alignment(0, 0.60),
                child: Opacity(
                  opacity: _clamp01(textOpacity),
                  child: Transform.scale(
                    scale: textIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _title(widget.type),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                color: Color(0xFFFFD54F),
                                shadows: [
                                  Shadow(
                                      color: Color(0xAA000000),
                                      blurRadius: 14),
                                ],
                              ),
                            ),
                          ),
                          if (widget.subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                widget.subtitle!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 1: stumps (bowled, hit wicket, stumped, run out)
// ---------------------------------------------------------------------------

class _WicketPainter extends CustomPainter {
  _WicketPainter(this.t, {required this.shatter});

  final double t;

  /// true  = stumps are knocked over as well (bowled, hit wicket)
  /// false = only the bails fly off (stumped, run out)
  final bool shatter;

  static const double _impact = 0.30;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final groundY = h * 0.50;
    final stumpH = math.min(w * 0.62, h * 0.34);
    final stumpW = stumpH * 0.085;
    final pitch = stumpW * 2.15;
    final fadeOut = 1 - _clamp01((t - 0.84) / 0.14);

    // little camera shake right after the hit
    final since = t - _impact;
    if (since > 0 && since < 0.14) {
      final amp = (1 - since / 0.14) * 7;
      canvas.translate(math.sin(t * 190) * amp, math.cos(t * 230) * amp);
    }

    // ground line
    canvas.drawLine(
      Offset(w * 0.10, groundY),
      Offset(w * 0.90, groundY),
      Paint()
        ..color = _c(255, 255, 255, 0.25 * fadeOut)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final p = _clamp01((t - _impact) / 0.55);
    final e = Curves.easeOutCubic.transform(p);
    final arc = math.sin(math.pi * p);
    final se = shatter ? e : 0.0;
    final sarc = shatter ? arc : 0.0;

    // ---- stumps
    final stumpFill = Paint()..color = _c(243, 225, 181, fadeOut);
    final stumpEdge = Paint()
      ..color = _c(184, 147, 90, fadeOut)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final stumpRadius = Radius.circular(stumpW * 0.35);

    for (var i = 0; i < 3; i++) {
      final baseX = cx + (i - 1) * pitch;
      canvas.save();
      if (i == 1) {
        // middle stump is hit: it cartwheels up and away
        canvas.translate(
          baseX + se * stumpH * 0.10,
          groundY - stumpH / 2 - sarc * stumpH * 0.55,
        );
        canvas.rotate(3.6 * se);
        final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(-stumpW / 2, -stumpH / 2, stumpW, stumpH),
          stumpRadius,
        );
        canvas.drawRRect(rr, stumpFill);
        canvas.drawRRect(rr, stumpEdge);
      } else {
        final dir = i == 0 ? -1.0 : 1.0;
        canvas.translate(
          baseX + dir * se * stumpH * (i == 0 ? 0.30 : 0.38),
          groundY - sarc * stumpH * 0.14,
        );
        canvas.rotate(dir * (i == 0 ? 1.25 : 1.1) * se);
        final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(-stumpW / 2, -stumpH, stumpW, stumpH),
          stumpRadius,
        );
        canvas.drawRRect(rr, stumpFill);
        canvas.drawRRect(rr, stumpEdge);
      }
      canvas.restore();
    }

    // ---- bails
    final bailW = pitch * 0.95;
    final bailH = stumpW * 0.5;
    final bailPaint = Paint()..color = _c(255, 213, 79, fadeOut);
    for (var j = 0; j < 2; j++) {
      final dir = j == 0 ? -1.0 : 1.0;
      final x0 = cx + (j - 0.5) * pitch;
      final y0 = groundY - stumpH - bailH / 2;
      final x = x0 + dir * (0.26 + 0.12 * j) * w * p;
      final y = y0 + (-1.5 * p + 1.9 * p * p) * stumpH;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(dir * 9 * p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: bailW, height: bailH),
          Radius.circular(bailH / 2),
        ),
        bailPaint,
      );
      canvas.restore();
    }

    // ---- ball
    final ballR = stumpW * 1.2;
    final hit = Offset(cx, groundY - stumpH * 0.52);
    Offset ball;
    if (t < _impact) {
      final b = t / _impact;
      ball = Offset(
        w * 1.08 + (hit.dx - w * 1.08) * b,
        groundY -
            stumpH * 1.25 +
            (hit.dy - (groundY - stumpH * 1.25)) * b * b -
            math.sin(math.pi * b) * stumpH * 0.12,
      );
    } else {
      final p2 = _clamp01((t - _impact) / 0.5);
      ball = Offset(
        hit.dx - p2 * w * 0.58,
        hit.dy + (-1.2 * p2 + 1.6 * p2 * p2) * stumpH * 0.9,
      );
    }
    _drawBall(canvas, ball, ballR, t * 28, fadeOut);

    // ---- impact sparks + shock ring
    final q = _clamp01((t - _impact) / 0.25);
    if (t > _impact && q < 1) {
      final spark = Paint()
        ..color = _c(255, 236, 130, 1 - q)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 14; k++) {
        final a = k * 2 * math.pi / 14 + 0.2;
        final d0 = (0.10 + 0.35 * q) * stumpH;
        final d1 = (0.20 + 0.60 * q) * stumpH;
        canvas.drawLine(
          hit + Offset(math.cos(a) * d0, math.sin(a) * d0),
          hit + Offset(math.cos(a) * d1, math.sin(a) * d1),
          spark,
        );
      }
    }
    final q2 = _clamp01((t - _impact) / 0.35);
    if (t > _impact && q2 < 1) {
      canvas.drawCircle(
        hit,
        stumpH * 0.95 * Curves.easeOut.transform(q2),
        Paint()
          ..color = _c(255, 255, 255, 0.55 * (1 - q2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WicketPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Scene 2: caught - the ball loops high into a pair of cupped hands
// ---------------------------------------------------------------------------

void _drawHand(
    Canvas canvas, Offset center, double hr, double angle, double alpha) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  final skin = Paint()..color = _c(224, 172, 105, alpha);
  final edge = Paint()
    ..color = _c(150, 100, 55, alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2;
  final palm = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: hr * 1.7, height: hr * 1.05),
    Radius.circular(hr * 0.5),
  );
  canvas.drawRRect(palm, skin);
  canvas.drawRRect(palm, edge);
  for (var i = 0; i < 4; i++) {
    final fx = (-0.62 + i * 0.41) * hr;
    final finger = RRect.fromRectAndRadius(
      Rect.fromLTWH(fx - hr * 0.17, -hr * 1.0, hr * 0.34, hr * 0.75),
      Radius.circular(hr * 0.17),
    );
    canvas.drawRRect(finger, skin);
    canvas.drawRRect(finger, edge);
  }
  canvas.restore();
}

/// Fielder in a completely blue shirt with a blank, faceless head and a blue
/// cap. His arms are bent so the cupped [hands] are just below his head.
void _drawFielder(
    Canvas canvas, Offset feet, double hr, Offset hands, double alpha) {
  final legH = hr * 2.0;
  final torsoH = hr * 2.2;
  final torsoW = hr * 1.7;
  final hipY = feet.dy - legH;
  final shoulderY = hipY - torsoH;
  final cx = feet.dx;

  // ---- colours: change these numbers (red, green, blue) to restyle him
  final skin = _c(224, 172, 105, alpha); // skin tone
  final shirt = _c(33, 110, 215, alpha); // blue shirt
  final shirtShade = _c(22, 80, 165, alpha); // darker blue (fold line)
  final sleeve = _c(24, 90, 180, alpha); // blue arms (a bit darker)
  final trousers = _c(245, 245, 245, alpha); // white trousers (try black: 25, 25, 28)
  final shoes = _c(25, 28, 33, alpha);
  final cap = _c(24, 90, 180, alpha); // blue cap
  final capBand = _c(15, 56, 120, alpha);

  // legs and shoes
  for (var i = 0; i < 2; i++) {
    final x = cx + (i == 0 ? -hr * 0.8 : hr * 0.1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, hipY, hr * 0.7, legH),
        Radius.circular(hr * 0.2),
      ),
      Paint()..color = trousers,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - hr * 0.1, feet.dy - hr * 0.2, hr * 0.9, hr * 0.3),
        Radius.circular(hr * 0.12),
      ),
      Paint()..color = shoes,
    );
  }

  // blue shirt with a soft centre fold
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - torsoW / 2, shoulderY, torsoW, torsoH),
      Radius.circular(hr * 0.5),
    ),
    Paint()..color = shirt,
  );
  canvas.drawLine(
    Offset(cx, shoulderY + hr * 1.5),
    Offset(cx, shoulderY + torsoH - hr * 0.1),
    Paint()
      ..color = shirtShade
      ..strokeWidth = hr * 0.08,
  );

  // arms: shoulder -> elbow (out and down) -> hand (in and up)
  final shL = Offset(cx - torsoW / 2 + hr * 0.2, shoulderY + hr * 0.3);
  final shR = Offset(cx + torsoW / 2 - hr * 0.2, shoulderY + hr * 0.3);
  final handL = hands + Offset(-hr * 0.5, hr * 0.45);
  final handR = hands + Offset(hr * 0.5, hr * 0.45);
  final elbowY = math.max(shoulderY + hr * 1.9, handL.dy + hr * 0.25);
  final elbowL = Offset(cx - torsoW / 2 - hr * 0.3, elbowY);
  final elbowR = Offset(cx + torsoW / 2 + hr * 0.3, elbowY);
  final arm = Paint()
    ..color = sleeve
    ..strokeWidth = hr * 0.52
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawLine(shL, elbowL, arm);
  canvas.drawLine(elbowL, handL, arm);
  canvas.drawLine(shR, elbowR, arm);
  canvas.drawLine(elbowR, handR, arm);

  // neck and blank head (no eyes, nose or mouth)
  canvas.drawRect(
    Rect.fromLTWH(cx - hr * 0.2, shoulderY - hr * 0.3, hr * 0.4, hr * 0.4),
    Paint()..color = skin,
  );
  final headC = Offset(cx, shoulderY - hr * 0.7);
  canvas.drawCircle(headC, hr * 0.72, Paint()..color = skin);

  // plain blue cap: dome, band and a short peak
  final domeC = Offset(cx, headC.dy - hr * 0.12);
  canvas.drawArc(
    Rect.fromCenter(center: domeC, width: hr * 1.5, height: hr * 1.5),
    math.pi,
    math.pi,
    true,
    Paint()..color = cap,
  );
  canvas.drawRect(
    Rect.fromLTWH(cx - hr * 0.75, domeC.dy - hr * 0.02, hr * 1.5, hr * 0.16),
    Paint()..color = capBand,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, domeC.dy + hr * 0.2),
        width: hr * 1.1,
        height: hr * 0.2,
      ),
      Radius.circular(hr * 0.1),
    ),
    Paint()..color = capBand,
  );
}

class _CaughtPainter extends CustomPainter {
  _CaughtPainter(this.t);

  final double t;

  static const double _catchAt = 0.58;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fadeOut = 1 - _clamp01((t - 0.86) / 0.12);
    final groundY = h * 0.62;
    final hr = math.min(w, h * 0.7) * 0.11;
    final ballR = hr * 0.62;
    final feetY = groundY + hr * 1.7;
    final start = Offset(w * 0.16, groundY - h * 0.02);
    final target = Offset(w * 0.74, feetY - hr * 3.7);

    canvas.drawLine(
      Offset(w * 0.08, groundY + hr * 1.7),
      Offset(w * 0.92, groundY + hr * 1.7),
      Paint()
        ..color = _c(255, 255, 255, 0.22 * fadeOut)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final u = _clamp01(t / _catchAt);

    Offset ballAt(double v) {
      return Offset(
        start.dx + (target.dx - start.dx) * v,
        start.dy +
            (target.dy - start.dy) * v -
            math.sin(math.pi * v) * h * 0.36,
      );
    }

    // hands rise to meet the ball, then bob when it lands
    final reach = (1 - Curves.easeOut.transform(u)) * hr * 1.4;
    final after = math.max(0.0, t - _catchAt);
    final bob = math.sin(after * 38) * math.exp(-after * 12) * hr * 0.18;
    final hands = target + Offset(0, reach + bob);

    // the fielder (red shirt, blank face)
    _drawFielder(canvas, Offset(target.dx, feetY), hr, hands, fadeOut);

    // back hand (behind the ball)
    _drawHand(canvas, hands + Offset(-hr * 0.5, hr * 0.45), hr, -0.55, fadeOut);

    // ball trail + ball
    if (t < _catchAt) {
      for (var k = 1; k <= 9; k++) {
        final uk = u - k * 0.028;
        if (uk < 0) break;
        canvas.drawCircle(
          ballAt(uk),
          ballR * (1 - k * 0.08),
          Paint()..color = _c(255, 255, 255, (0.45 - k * 0.045) * fadeOut),
        );
      }
      _drawBall(canvas, ballAt(u), ballR, t * 24, fadeOut);
    } else {
      _drawBall(canvas, hands + Offset(0, -hr * 0.05), ballR, 0.8, fadeOut);
    }

    // front hand (in front of the ball)
    _drawHand(canvas, hands + Offset(hr * 0.5, hr * 0.45), hr, 0.55, fadeOut);

    // "pop" when the ball is held
    final q = _clamp01((t - _catchAt) / 0.30);
    if (t > _catchAt && q < 1) {
      canvas.drawCircle(
        hands,
        hr * 3.0 * Curves.easeOut.transform(q),
        Paint()
          ..color = _c(255, 255, 255, 0.6 * (1 - q))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      final spark = Paint()
        ..color = _c(255, 236, 130, 1 - q)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 10; k++) {
        final a = k * 2 * math.pi / 10;
        final d0 = hr * (1.2 + 1.2 * q);
        final d1 = hr * (1.7 + 2.0 * q);
        canvas.drawLine(
          hands + Offset(math.cos(a) * d0, math.sin(a) * d0),
          hands + Offset(math.cos(a) * d1, math.sin(a) * d1),
          spark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CaughtPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Scene 3: LBW - ball hits the pad, tracking line to the stumps, umpire's finger
// ---------------------------------------------------------------------------

void _drawUmpire(
    Canvas canvas, Offset feet, double u, double theta, double alpha) {
  final legH = u * 2.0;
  final torsoH = u * 2.3;
  final torsoW = u * 1.9;
  final hipY = feet.dy - legH;
  final shoulderY = hipY - torsoH;
  final cx = feet.dx;
  final white = Paint()..color = _c(250, 250, 250, alpha);
  final skin = _c(224, 172, 105, alpha);
  final dark = Paint()..color = _c(33, 37, 41, alpha);
  final sleeve = Paint()
    ..color = _c(250, 250, 250, alpha)
    ..strokeWidth = u * 0.62
    ..strokeCap = StrokeCap.round;

  // legs
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - u * 0.8, hipY, u * 0.7, legH), Radius.circular(u * 0.2)),
    dark,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + u * 0.1, hipY, u * 0.7, legH), Radius.circular(u * 0.2)),
    dark,
  );

  // arm hanging down (left)
  final shL = Offset(cx - torsoW / 2 + u * 0.15, shoulderY + u * 0.35);
  canvas.drawLine(shL, shL + Offset(-u * 0.15, u * 1.9), sleeve);

  // torso + belt
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - torsoW / 2, shoulderY, torsoW, torsoH),
        Radius.circular(u * 0.5)),
    white,
  );
  canvas.drawRect(
      Rect.fromLTWH(cx - torsoW / 2, hipY - u * 0.25, torsoW, u * 0.25), dark);

  // head and hat
  final headC = Offset(cx, shoulderY - u * 0.85);
  canvas.drawCircle(headC, u * 0.78, Paint()..color = skin);
  final hatC = headC + Offset(0, -u * 0.55);
  canvas.drawArc(
    Rect.fromCenter(center: hatC, width: u * 1.7, height: u * 1.5),
    math.pi,
    math.pi,
    true,
    Paint()..color = _c(245, 245, 245, alpha),
  );
  canvas.drawOval(
    Rect.fromCenter(center: hatC, width: u * 2.5, height: u * 0.55),
    Paint()..color = _c(235, 235, 235, alpha),
  );

  // raised arm (right) with pointing finger.  theta: 0 = down, pi = straight up
  final shR = Offset(cx + torsoW / 2 - u * 0.15, shoulderY + u * 0.35);
  final dir = Offset(math.sin(theta), math.cos(theta));
  final handP = shR + dir * (u * 2.0);
  canvas.drawLine(shR, handP, sleeve);
  canvas.drawCircle(handP, u * 0.34, Paint()..color = skin);
  canvas.drawLine(
    handP,
    handP + dir * (u * 0.95),
    Paint()
      ..color = skin
      ..strokeWidth = u * 0.26
      ..strokeCap = StrokeCap.round,
  );
}

class _LbwPainter extends CustomPainter {
  _LbwPainter(this.t);

  final double t;

  static const double _hitAt = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fadeOut = 1 - _clamp01((t - 0.86) / 0.12);
    final groundY = h * 0.62;
    final u = math.min(w, h * 0.7) * 0.10;

    canvas.drawLine(
      Offset(w * 0.06, groundY),
      Offset(w * 0.94, groundY),
      Paint()
        ..color = _c(255, 255, 255, 0.22 * fadeOut)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // ---- stumps (left)
    final stumpH = u * 3.4;
    final stumpW = u * 0.34;
    final sx = w * 0.14;
    final pitchS = stumpW * 2.2;
    final stumpFill = Paint()..color = _c(243, 225, 181, fadeOut);
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              sx + (i - 1) * pitchS - stumpW / 2, groundY - stumpH, stumpW, stumpH),
          Radius.circular(stumpW * 0.35),
        ),
        stumpFill,
      );
    }
    final bail = Paint()..color = _c(255, 213, 79, fadeOut);
    for (var j = 0; j < 2; j++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(sx + (j - 0.5) * pitchS, groundY - stumpH - stumpW * 0.2),
            width: pitchS * 0.95,
            height: stumpW * 0.5,
          ),
          Radius.circular(stumpW * 0.25),
        ),
        bail,
      );
    }

    // ---- pad (the batter's leg guard)
    final padW = u * 1.5;
    final padH = u * 4.2;
    final padC = Offset(w * 0.40, groundY - padH / 2 - u * 0.1);
    canvas.save();
    canvas.translate(padC.dx, padC.dy);
    canvas.rotate(0.12);
    final pad = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: padW, height: padH),
      Radius.circular(padW * 0.4),
    );
    canvas.drawRRect(pad, Paint()..color = _c(245, 240, 225, fadeOut));
    canvas.drawRRect(
      pad,
      Paint()
        ..color = _c(150, 140, 120, fadeOut)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    final strap = Paint()
      ..color = _c(150, 140, 120, fadeOut)
      ..strokeWidth = 2.5;
    for (var k = 0; k < 3; k++) {
      final y = -padH * 0.28 + k * padH * 0.26;
      canvas.drawLine(Offset(-padW * 0.5, y), Offset(padW * 0.5, y), strap);
    }
    canvas.restore();

    // ---- ball arrives and hits the pad
    final hitP = padC + Offset(padW * 0.15, -padH * 0.12);
    final from = Offset(w * 0.98, h * 0.10);
    final ballR = u * 0.34;
    if (t < _hitAt) {
      final b = Curves.easeIn.transform(t / _hitAt);
      final pos = Offset(
        from.dx + (hitP.dx - from.dx) * b,
        from.dy + (hitP.dy - from.dy) * b,
      );
      for (var k = 1; k <= 7; k++) {
        final bk = b - k * 0.035;
        if (bk < 0) break;
        canvas.drawCircle(
          Offset(
            from.dx + (hitP.dx - from.dx) * bk,
            from.dy + (hitP.dy - from.dy) * bk,
          ),
          ballR * (1 - k * 0.1),
          Paint()..color = _c(255, 255, 255, (0.4 - k * 0.05) * fadeOut),
        );
      }
      _drawBall(canvas, pos, ballR, t * 30, fadeOut);
    }

    // impact ring on the pad
    final q = _clamp01((t - _hitAt) / 0.18);
    if (t > _hitAt && q < 1) {
      canvas.drawCircle(
        hitP,
        u * 1.7 * Curves.easeOut.transform(q),
        Paint()
          ..color = _c(255, 213, 79, 0.9 * (1 - q))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }

    // ---- ball-tracking line from the pad to the stumps
    final target = Offset(sx, groundY - stumpH * 0.55);
    final s = _clamp01((t - _hitAt) / 0.28);
    if (t > _hitAt) {
      const dots = 14;
      for (var k = 0; k < dots; k++) {
        final f = k / dots;
        if (f > s) break;
        canvas.drawCircle(
          Offset.lerp(hitP, target, f)!,
          u * 0.09,
          Paint()..color = _c(255, 167, 38, 0.95 * fadeOut),
        );
      }
      final ghost = Offset.lerp(hitP, target, Curves.easeInOut.transform(s))!;
      canvas.drawCircle(
        ghost,
        ballR,
        Paint()..color = _c(198, 40, 40, 0.55 * fadeOut),
      );
      if (s >= 1) {
        canvas.drawCircle(
          target,
          u * 0.7,
          Paint()
            ..color = _c(255, 167, 38, 0.8 * fadeOut)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }

    // ---- umpire raises his finger
    final raise = Curves.easeOutBack.transform(_clamp01((t - 0.50) / 0.26));
    _drawUmpire(canvas, Offset(w * 0.80, groundY), u, raise * math.pi, fadeOut);
  }

  @override
  bool shouldRepaint(covariant _LbwPainter old) => old.t != t;
}

// ===========================================================================
// WIN CELEBRATION  (party poppers, confetti, trophy, "TEAM won!")
// ===========================================================================

/// Full-screen celebration. Returns true when the user taps "View scorecard".
/// Pass [winnerName] = null for a tie (no confetti).
Future<bool?> showWinCelebration(
  BuildContext context, {
  String? winnerName,
  required String detail,
}) {
  if (winnerName != null) HapticFeedback.mediumImpact();
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xCC000000),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (ctx, a1, a2) =>
        _WinPage(winnerName: winnerName, detail: detail),
    transitionBuilder: (ctx, anim, secondary, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

const List<Color> _palette = [
  Color(0xFFFF5252),
  Color(0xFFFFD740),
  Color(0xFF69F0AE),
  Color(0xFF40C4FF),
  Color(0xFFE040FB),
  Color(0xFFFF9100),
  Color(0xFFFFFFFF),
];

class _Particle {
  const _Particle({
    required this.src,
    required this.x0,
    required this.kind,
    required this.color,
    required this.size,
    required this.spin,
    required this.spinSpeed,
    required this.flipSpeed,
    required this.delay,
    required this.vx,
    required this.vy,
    required this.fall,
    required this.wobble,
    required this.wobblePhase,
  });

  final int src; // 0 = left popper, 1 = right popper, 2 = falls from the top
  final double x0; // only for src 2 (fraction of width)
  final int kind; // 0 = paper, 1 = dot, 2 = streamer
  final Color color;
  final double size;
  final double spin;
  final double spinSpeed;
  final double flipSpeed;
  final double delay;
  final double vx;
  final double vy;
  final double fall;
  final double wobble;
  final double wobblePhase;
}

const double _confettiSeconds = 10.0;

List<_Particle> _buildParticles() {
  final r = math.Random();
  final list = <_Particle>[];

  for (var side = 0; side < 2; side++) {
    for (var i = 0; i < 95; i++) {
      final spread = 0.45 + (r.nextDouble() - 0.5) * 1.2;
      final phi = side == 0 ? spread : -spread;
      final speed = 1.1 + r.nextDouble() * 1.7;
      final roll = r.nextInt(10);
      list.add(_Particle(
        src: side,
        x0: 0,
        kind: roll < 6 ? 0 : (roll < 8 ? 1 : 2),
        color: _palette[r.nextInt(_palette.length)],
        size: 7 + r.nextDouble() * 8,
        spin: r.nextDouble() * 6.28,
        spinSpeed: (r.nextDouble() - 0.5) * 14,
        flipSpeed: 4 + r.nextDouble() * 8,
        delay: 0.18 + r.nextDouble() * 0.12,
        vx: math.sin(phi) * speed,
        vy: -math.cos(phi) * speed,
        fall: 0.30 + r.nextDouble() * 0.35,
        wobble: 3 + r.nextDouble() * 4,
        wobblePhase: r.nextDouble() * 6.28,
      ));
    }
  }

  for (var i = 0; i < 90; i++) {
    final roll = r.nextInt(10);
    list.add(_Particle(
      src: 2,
      x0: r.nextDouble(),
      kind: roll < 6 ? 0 : (roll < 8 ? 1 : 2),
      color: _palette[r.nextInt(_palette.length)],
      size: 7 + r.nextDouble() * 8,
      spin: r.nextDouble() * 6.28,
      spinSpeed: (r.nextDouble() - 0.5) * 10,
      flipSpeed: 4 + r.nextDouble() * 8,
      delay: 0.8 + r.nextDouble() * 4.2,
      vx: (r.nextDouble() - 0.5) * 0.15,
      vy: 0,
      fall: 0.30 + r.nextDouble() * 0.35,
      wobble: 2 + r.nextDouble() * 3,
      wobblePhase: r.nextDouble() * 6.28,
    ));
  }
  return list;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.seconds);

  final List<_Particle> particles;
  final double seconds;

  static const double _k = 1.6; // air drag

  void _drawPopper(Canvas canvas, Offset base, double angle, double alpha) {
    if (alpha <= 0) return;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final cone = Path()
      ..moveTo(-6, 0)
      ..lineTo(6, 0)
      ..lineTo(22, -60)
      ..lineTo(-22, -60)
      ..close();
    canvas.drawPath(cone, Paint()..color = _c(255, 112, 67, alpha));
    final stripe = Paint()
      ..color = _c(255, 235, 59, alpha)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-10, -20), const Offset(10, -20), stripe);
    canvas.drawLine(const Offset(-15, -40), const Offset(15, -40), stripe);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -60), width: 44, height: 11),
      Paint()..color = _c(255, 255, 255, alpha),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    const tilt = 0.45;
    final baseY = size.height - 28;
    final leftBase = Offset(size.width * 0.10, baseY);
    final rightBase = Offset(size.width * 0.90, baseY);
    final leftMouth = leftBase + Offset(60 * math.sin(tilt), -60 * math.cos(tilt));
    final rightMouth =
        rightBase + Offset(60 * math.sin(-tilt), -60 * math.cos(-tilt));

    // poppers: visible for the first moments, then fade away
    final popAlpha = 1 - _clamp01((seconds - 1.0) / 0.8);
    _drawPopper(canvas, leftBase, tilt, popAlpha);
    _drawPopper(canvas, rightBase, -tilt, popAlpha);

    final fadeAll = _clamp01((_confettiSeconds - seconds) / 1.2);

    for (final p in particles) {
      final tt = seconds - p.delay;
      if (tt <= 0) continue;
      final drag = (1 - math.exp(-_k * tt)) / _k;

      Offset origin;
      if (p.src == 0) {
        origin = leftMouth;
      } else if (p.src == 1) {
        origin = rightMouth;
      } else {
        origin = Offset(p.x0 * size.width, -20);
      }

      final wobble =
          math.sin(tt * p.wobble + p.wobblePhase) * unit * 0.02 * math.min(tt, 1.5);
      final x = origin.dx + p.vx * unit * drag + wobble;
      final y = origin.dy + p.vy * unit * drag + p.fall * unit * (tt - drag);
      if (y > size.height + 40 || x < -60 || x > size.width + 60) continue;

      final paint = Paint()..color = p.color.withAlpha((255 * fadeAll).round());

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin + p.spinSpeed * tt);
      if (p.kind == 0) {
        var flip = math.cos(tt * p.flipSpeed + p.wobblePhase);
        if (flip.abs() < 0.15) flip = flip < 0 ? -0.15 : 0.15;
        canvas.scale(1.0, flip);
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.55),
          paint,
        );
      } else if (p.kind == 1) {
        canvas.drawCircle(Offset.zero, p.size * 0.32, paint);
      } else {
        final path = Path()
          ..moveTo(-p.size, 0)
          ..quadraticBezierTo(-p.size / 2, -p.size * 0.5, 0, 0)
          ..quadraticBezierTo(p.size / 2, p.size * 0.5, p.size, 0);
        canvas.drawPath(
          path,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.seconds != seconds;
}

class _WinPage extends StatefulWidget {
  const _WinPage({required this.winnerName, required this.detail});

  final String? winnerName;
  final String detail;

  @override
  State<_WinPage> createState() => _WinPageState();
}

class _WinPageState extends State<_WinPage> with TickerProviderStateMixin {
  late final AnimationController _confetti;
  late final AnimationController _pulse;
  late final AnimationController _intro;
  late final List<_Particle> _particles;

  bool get _celebrate => widget.winnerName != null;

  @override
  void initState() {
    super.initState();
    _particles = _celebrate ? _buildParticles() : <_Particle>[];
    _confetti = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_confettiSeconds * 1000).round()),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    if (_celebrate) _confetti.forward();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _pulse.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _replay() {
    if (_celebrate) {
      HapticFeedback.lightImpact();
      _confetti.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final introScale = CurvedAnimation(parent: _intro, curve: Curves.elasticOut);
    final trophyScale = Tween<double>(begin: 0.93, end: 1.07).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.15,
                  colors: _celebrate
                      ? const [
                          Color(0xFF1B7F52),
                          Color(0xFF0B3D2A),
                          Color(0xFF04120C),
                        ]
                      : const [
                          Color(0xFF37474F),
                          Color(0xFF1C272C),
                          Color(0xFF0A0F11),
                        ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _replay,
                      child: ScaleTransition(
                        scale: trophyScale,
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _c(255, 213, 79, _celebrate ? 0.45 : 0.15),
                                blurRadius: 60,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            _celebrate ? Icons.emoji_events : Icons.handshake,
                            size: 120,
                            color: const Color(0xFFFFD54F),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _celebrate ? 'WINNER' : 'MATCH TIED',
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontSize: 16,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_celebrate) ...[
                      const SizedBox(height: 8),
                      ScaleTransition(
                        scale: introScale,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.winnerName!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(
                                    color: Color(0x99000000), blurRadius: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      widget.detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD54F),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.table_chart),
                      label: const Text('View scorecard'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_celebrate)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) => CustomPaint(
                    painter: _ConfettiPainter(
                      _particles,
                      _confetti.value * _confettiSeconds,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
