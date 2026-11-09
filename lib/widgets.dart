import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// Drop-down listing players. With [allowNone] an extra "-" entry lets the
/// user clear the choice.
class PlayerDropdown extends StatelessWidget {
  const PlayerDropdown({
    super.key,
    required this.label,
    required this.players,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
  });

  final String label;
  final List<Player> players;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      if (allowNone)
        const DropdownMenuItem<String>(value: '', child: Text('-')),
      for (final p in players)
        DropdownMenuItem<String>(value: p.id, child: Text(p.name)),
    ];
    final selected = value ?? (allowNone ? '' : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: selected,
            hint: const Text('Select'),
            items: items,
            onChanged: (v) => onChanged((v == null || v.isEmpty) ? null : v),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'Yes',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<T?> pickOne<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) label,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final item in items)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, item),
            child: Text(label(item)),
          ),
      ],
    ),
  );
}

/// Result of the "start innings" dialog.
class InningsSetup {
  const InningsSetup(this.strikerId, this.nonStrikerId, this.bowlerId);

  final String strikerId;
  final String nonStrikerId;
  final String bowlerId;
}

/// Forces the scorer to choose striker, non-striker and opening bowler
/// before the first ball of an innings.
class InningsSetupDialog extends StatefulWidget {
  const InningsSetupDialog({
    super.key,
    required this.batting,
    required this.bowling,
  });

  final MatchSide batting;
  final MatchSide bowling;

  @override
  State<InningsSetupDialog> createState() => _InningsSetupDialogState();
}

class _InningsSetupDialogState extends State<InningsSetupDialog> {
  String? _striker;
  String? _non;
  String? _bowler;

  @override
  Widget build(BuildContext context) {
    final ready = _striker != null && _non != null && _bowler != null;
    return AlertDialog(
      title: Text('${widget.batting.name} to bat'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerDropdown(
              label: 'Striker',
              players:
                  widget.batting.players.where((p) => p.id != _non).toList(),
              value: _striker,
              onChanged: (v) => setState(() => _striker = v),
            ),
            PlayerDropdown(
              label: 'Non-striker',
              players: widget.batting.players
                  .where((p) => p.id != _striker)
                  .toList(),
              value: _non,
              onChanged: (v) => setState(() => _non = v),
            ),
            PlayerDropdown(
              label: 'Opening bowler (${widget.bowling.name})',
              players: widget.bowling.players,
              value: _bowler,
              onChanged: (v) => setState(() => _bowler = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready
              ? () => Navigator.pop(
                    context,
                    InningsSetup(_striker!, _non!, _bowler!),
                  )
              : null,
          child: const Text('Start innings'),
        ),
      ],
    );
  }
}

/// A red cricket ball with a white seam and stitches (used instead of the
/// round "baseball / tennis" material icon).
class CricketBallIcon extends StatelessWidget {
  const CricketBallIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CricketBallPainter()),
    );
  }
}

class _CricketBallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    paintCricketBall(
      canvas,
      Offset(size.width / 2, size.height / 2),
      size.shortestSide / 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CricketBallPainter old) => false;
}

/// Draws a leather cricket ball: dark red glossy leather, two raised seam
/// ridges with tan stitching between them, and a soft highlight.
/// [tilt] turns the seam (the light stays fixed); [alpha] fades the whole ball.
void paintCricketBall(Canvas canvas, Offset c, double r,
    {double tilt = 0.55, double alpha = 1.0}) {
  final circle = Rect.fromCircle(center: c, radius: r);
  final layered = alpha < 0.99;
  if (layered) {
    canvas.saveLayer(
      circle.inflate(r * 0.2),
      Paint()..color = Color.fromRGBO(0, 0, 0, alpha < 0 ? 0.0 : alpha),
    );
  }

  // leather
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.4, -0.45),
        radius: 1.1,
        colors: [Color(0xFFC8434A), Color(0xFF9B1C26), Color(0xFF3F0910)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(circle),
  );

  canvas.save();
  canvas.clipPath(Path()..addOval(circle));
  canvas.translate(c.dx, c.dy);
  canvas.rotate(tilt);

  final b = r * 1.2; // seam runs off the ball on both ends
  final a1 = r * 0.20;
  final a2 = r * 0.42;
  final am = (a1 + a2) / 2;
  Rect oval(double a, [double dx = 0, double dy = 0]) =>
      Rect.fromCenter(center: Offset(dx, dy), width: a * 2, height: b * 2);

  // dark channel between the two ridges
  canvas.drawOval(
    oval(am),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = a2 - a1
      ..color = const Color(0xFF5E0B12),
  );

  // tan stitches crossing the channel
  final thread = Paint()
    ..color = const Color(0xFFE2A85A)
    ..strokeWidth = math.max(1.0, r * 0.07)
    ..strokeCap = StrokeCap.round;
  const stitches = 24;
  for (var k = 0; k < stitches; k++) {
    final t = k * 2 * math.pi / stitches;
    final s = math.sin(t);
    if (s.abs() > 0.92) continue;
    final y = b * s;
    final step = r * 0.07;
    canvas.drawLine(
      Offset(a1 * math.cos(t), y - step),
      Offset(a2 * math.cos(t), y + step),
      thread,
    );
  }

  // the two raised ridges (shadow, leather, light edge)
  final ridgeW = r * 0.13;
  for (final a in [a1, a2]) {
    canvas.drawOval(
      oval(a, r * 0.03, r * 0.03),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ridgeW
        ..color = const Color(0x66000000),
    );
    canvas.drawOval(
      oval(a),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ridgeW
        ..color = const Color(0xFFA8242E),
    );
    canvas.drawOval(
      oval(a, -r * 0.025, -r * 0.025),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ridgeW * 0.35
        ..color = const Color(0x55FFFFFF),
    );
  }
  canvas.restore();

  // glossy highlight
  final hc = c + Offset(-r * 0.36, -r * 0.42);
  canvas.drawCircle(
    hc,
    r * 0.34,
    Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromCircle(center: hc, radius: r * 0.34)),
  );

  if (layered) canvas.restore();
}

/// A coloured cricket bat (wooden blade, blue grip) drawn at an angle.
class CricketBatIcon extends StatelessWidget {
  const CricketBatIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CricketBatPainter()),
    );
  }
}

class _CricketBatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(0.7);

    final top = -s * 0.46;
    final handleW = s * 0.12;
    final handleH = s * 0.30;
    final bladeW = s * 0.34;
    final bladeTop = top + handleH - s * 0.02;
    final bladeH = s * 0.66;

    // handle with coloured grip bands
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-handleW / 2, top, handleW, handleH),
        Radius.circular(handleW * 0.4),
      ),
      Paint()..color = const Color(0xFF5D4037),
    );
    final grip = Paint()
      ..color = const Color(0xFF1E88E5)
      ..strokeWidth = s * 0.035;
    for (var k = 0; k < 4; k++) {
      final y = top + handleH * 0.12 + k * handleH * 0.2;
      canvas.drawLine(Offset(-handleW / 2, y), Offset(handleW / 2, y), grip);
    }

    // wooden blade
    final bladeRect = Rect.fromLTWH(-bladeW / 2, bladeTop, bladeW, bladeH);
    final blade = RRect.fromRectAndCorners(
      bladeRect,
      topLeft: Radius.circular(bladeW * 0.25),
      topRight: Radius.circular(bladeW * 0.25),
      bottomLeft: Radius.circular(bladeW * 0.2),
      bottomRight: Radius.circular(bladeW * 0.2),
    );
    canvas.drawRRect(
      blade,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF2D49B), Color(0xFFD9A55B), Color(0xFFB9803D)],
        ).createShader(bladeRect),
    );
    canvas.drawRRect(
      blade,
      Paint()
        ..color = const Color(0xFF8D5A2B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.025,
    );
    canvas.drawLine(
      Offset(0, bladeTop + bladeH * 0.1),
      Offset(0, bladeTop + bladeH * 0.92),
      Paint()
        ..color = const Color(0x558D5A2B)
        ..strokeWidth = s * 0.03,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CricketBatPainter old) => false;
}
