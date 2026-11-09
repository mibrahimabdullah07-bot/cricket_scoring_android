import 'package:flutter/material.dart';

import 'models.dart';
import 'widgets.dart';

class WicketInput {
  const WicketInput({
    required this.type,
    required this.outId,
    required this.runs,
    required this.fielderId,
    required this.newBatterOnStrike,
  });

  final WicketType type;
  final String outId;
  final int runs;
  final String? fielderId;
  final bool newBatterOnStrike;
}

/// Asks how the batter was dismissed. Only dismissals that are possible on
/// the selected kind of delivery are offered (e.g. only a run out on a
/// no-ball).
class WicketDialog extends StatefulWidget {
  const WicketDialog({
    super.key,
    required this.mode,
    required this.strikerId,
    required this.nonStrikerId,
    required this.batting,
    required this.bowling,
    this.freeHit = false,
  });

  final DeliveryKind mode;
  final String strikerId;
  final String nonStrikerId;
  final MatchSide batting;
  final MatchSide bowling;

  /// Free hit (the ball after a no-ball): only a run out is possible.
  final bool freeHit;

  @override
  State<WicketDialog> createState() => _WicketDialogState();
}

class _WicketDialogState extends State<WicketDialog> {
  late final List<WicketType> _types;
  late WicketType _type;
  late String _outId;
  int _runs = 0;
  String? _fielder;
  bool? _onStrikeOverride;

  @override
  void initState() {
    super.initState();
    _types = WicketType.values
        .where((t) =>
            t.allowedOn(widget.mode) &&
            (!widget.freeHit || t == WicketType.runOut))
        .toList();
    _type = _types.first;
    _outId = widget.strikerId;
  }

  @override
  Widget build(BuildContext context) {
    final isRunOut = _type == WicketType.runOut;
    final defaultOnStrike = (_outId == widget.strikerId) != _runs.isOdd;
    final onStrike = isRunOut ? (_onStrikeOverride ?? defaultOnStrike) : true;
    final showFielder =
        _type == WicketType.caught || _type == WicketType.stumped || isRunOut;
    final fielderLabel = switch (_type) {
      WicketType.caught => 'Caught by (optional)',
      WicketType.stumped => 'Wicketkeeper (optional)',
      _ => 'Fielder (optional)',
    };
    final titleStyle = Theme.of(context).textTheme.titleSmall;

    return AlertDialog(
      title: Text('Wicket (${widget.mode.label})'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How out?', style: titleStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _fielder = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isRunOut
                  ? 'Run out: no wicket credit for the bowler.'
                  : 'Credited to the bowler. Striker is out.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isRunOut) ...[
              const SizedBox(height: 12),
              Text('Batter out', style: titleStyle),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('${widget.batting.nameOf(widget.strikerId)} (striker)'),
                    selected: _outId == widget.strikerId,
                    onSelected: (_) => setState(() => _outId = widget.strikerId),
                  ),
                  ChoiceChip(
                    label: Text(widget.batting.nameOf(widget.nonStrikerId)),
                    selected: _outId == widget.nonStrikerId,
                    onSelected: (_) =>
                        setState(() => _outId = widget.nonStrikerId),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Runs completed before the run out', style: titleStyle),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in const [0, 1, 2, 3])
                    ChoiceChip(
                      label: Text('$r'),
                      selected: _runs == r,
                      onSelected: (_) => setState(() => _runs = r),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('New batter on strike'),
                value: onStrike,
                onChanged: (v) => setState(() => _onStrikeOverride = v),
              ),
            ],
            if (showFielder)
              PlayerDropdown(
                label: fielderLabel,
                players: widget.bowling.players,
                value: _fielder,
                allowNone: true,
                onChanged: (v) => setState(() => _fielder = v),
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
          onPressed: () => Navigator.pop(
            context,
            WicketInput(
              type: _type,
              outId: isRunOut ? _outId : widget.strikerId,
              runs: isRunOut ? _runs : 0,
              fielderId: showFielder ? _fielder : null,
              newBatterOnStrike: onStrike,
            ),
          ),
          child: const Text('Record wicket'),
        ),
      ],
    );
  }
}
