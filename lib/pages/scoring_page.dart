import 'package:flutter/material.dart';

import '../animations.dart';
import '../engine.dart';
import '../models.dart';
import '../store.dart';
import '../wagon_wheel.dart';
import '../widgets.dart';
import '../wicket_dialog.dart';
import 'scorecard_page.dart';

/// Live scoring screen for the most recent innings of a match.
///
/// The scorer only enters what happens on each ball. Everything else
/// (totals, overs, strike changes, bowler/batter figures, innings end,
/// target, result) is derived by [computeInnings].
class ScoringPage extends StatefulWidget {
  const ScoringPage({super.key, required this.store, required this.match});

  final AppStore store;
  final CricketMatch match;

  @override
  State<ScoringPage> createState() => _ScoringPageState();
}

class _ScoringPageState extends State<ScoringPage> {
  late InningsState _st;
  DeliveryKind _mode = DeliveryKind.normal;
  RunSource _nbSource = RunSource.bat;
  bool _busy = false; // a prompt dialog is currently open
  bool _firstDoneShown = false;
  bool _resultShown = false;

  CricketMatch get match => widget.match;
  int get _idx => match.innings.length - 1;
  Innings get _inn => match.innings[_idx];

  @override
  void initState() {
    super.initState();
    _recompute();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptPending());
  }

  void _recompute() {
    _st = computeInnings(match, _idx);
    if (!_st.complete) {
      if (_idx == 0) _firstDoneShown = false;
      if (_idx == 1) _resultShown = false;
    }
  }

  /// Redraw, save to local storage, then ask for whatever is missing next.
  Future<void> _commit() async {
    _recompute();
    if (mounted) setState(() {});
    await widget.store.upsertMatch(match);
    if (!mounted) return;
    _promptPending();
  }

  // ------------------------------------------------------------------
  // Automatic prompts (openers -> new batter -> new bowler -> innings end)
  // ------------------------------------------------------------------

  Future<void> _promptPending() async {
    if (!mounted || _busy) return;
    final st = _st;
    if (st.needsOpeners) {
      await _openersDialog();
    } else if (st.needsNewBatter) {
      await _pickNewBatter();
    } else if (st.needsBowler) {
      await _pickBowler();
    } else if (st.complete) {
      if (_idx == 0 && !_firstDoneShown) {
        _firstDoneShown = true;
        await _firstInningsDone();
      } else if (_idx == 1 && !_resultShown) {
        _resultShown = true;
        await _matchDone();
      }
    }
  }

  Future<void> _openersDialog() async {
    _busy = true;
    final setup = await showDialog<InningsSetup>(
      context: context,
      builder: (_) => InningsSetupDialog(
        batting: match.battingSide(_inn),
        bowling: match.bowlingSide(_inn),
      ),
    );
    _busy = false;
    if (setup == null || !mounted) return;
    _inn.openStrikerId = setup.strikerId;
    _inn.openNonStrikerId = setup.nonStrikerId;
    _inn.nextBowlerId = setup.bowlerId;
    await _commit();
  }

  Future<void> _pickNewBatter() async {
    final bat = match.battingSide(_inn);
    final candidates =
        bat.players.where((p) => !_st.batters.containsKey(p.id)).toList();
    if (candidates.isEmpty || _inn.deliveries.isEmpty) return;
    _busy = true;
    final picked = await pickOne<Player>(
      context,
      title: 'Select next batter',
      items: candidates,
      label: (p) => p.name,
    );
    _busy = false;
    if (picked == null || !mounted) return;
    _inn.deliveries.last.newBatterId = picked.id;
    await _commit();
  }

  Future<void> _pickBowler() async {
    final bowl = match.bowlingSide(_inn);
    final maxOvers = _st.maxOversPerBowler;
    // ICC rules: a bowler may not bowl two overs in a row, and may not bowl
    // more than one fifth of the innings (4 overs in a T20).
    final rested =
        bowl.players.where((p) => p.id != _st.lastOverBowlerId).toList();
    final eligible = rested.where((p) {
      final b = _st.bowlers[p.id];
      return b == null || b.balls < maxOvers * 6;
    }).toList();
    final relaxed = eligible.isEmpty;
    final candidates = relaxed ? rested : eligible;
    _busy = true;
    final p = await pickOne<Player>(
      context,
      title: relaxed
          ? 'Select a Bowler for over ${_st.legalBalls ~/ 6 + 1} (limit of $maxOvers overs relaxed)'
          : 'Select a Bowler for over ${_st.legalBalls ~/ 6 + 1}',
      items: candidates,
      label: (p) {
        final b = _st.bowlers[p.id];
        return b == null
            ? '${p.name}  (0 of $maxOvers overs)'
            : '${p.name}  (${b.overs} of $maxOvers overs, ${b.runs} runs, ${b.wickets} wickets)';
      },
    );
    _busy = false;
    if (p == null || !mounted) {
      // Dialog closed without a choice: the banner stays on screen so the
      // scorer can tap "Select bowler" again (or undo the last ball).
      if (mounted) setState(() {});
      return;
    }
    _inn.nextBowlerId = p.id;
    await _commit();
  }

  Future<void> _firstInningsDone() async {
    _busy = true;
    final start = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Innings complete'),
        content: Text(
          '${_st.battingTeamName} ${_st.runs}/${_st.wickets} '
          '(${oversText(_st.legalBalls)} overs) - ${_st.completeReason}.\n\n'
          'Target for ${_st.bowlingTeamName}: ${_st.runs + 1}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start second innings'),
          ),
        ],
      ),
    );
    _busy = false;
    if (start == true && mounted) await _startSecond();
  }

  Future<void> _matchDone() async {
    _busy = true;
    final result = matchResult(match);
    final winner = result?.winnerIndex;
    String? winnerName;
    var detail = result?.text ?? 'Innings complete';
    if (winner != null) {
      winnerName = match.sides[winner].name;
      if (detail.startsWith(winnerName)) {
        detail = detail.substring(winnerName.length).trim();
      }
    }
    final view = await showWinCelebration(
      context,
      winnerName: winnerName,
      detail: detail,
    );
    _busy = false;
    if (view == true && mounted) _openScorecard();
  }

  Future<void> _startSecond() async {
    if (match.innings.length != 1) return;
    match.innings.add(Innings(battingIndex: 1 - match.innings[0].battingIndex));
    _mode = DeliveryKind.normal;
    _nbSource = RunSource.bat;
    await _commit();
  }

  // ------------------------------------------------------------------
  // Scoring actions
  // ------------------------------------------------------------------

  Future<void> _apply(Delivery d) async {
    _inn.deliveries.add(d);
    _inn.nextBowlerId = null; // consumed; must be chosen again after the over
    _mode = DeliveryKind.normal;
    _nbSource = RunSource.bat;
    _recompute();
    if (mounted) setState(() {});
    await widget.store.upsertMatch(match); // saved before any animation
    if (!mounted) return;
    if (d.isWicket) {
      final out = _st.batters[d.outId ?? d.strikerId];
      await playWicketAnimation(
        context,
        subtitle: out == null ? null : '${out.name}  ${out.dismissal}',
        type: d.wicket,
      );
      if (!mounted) return;
    }
    _promptPending();
  }

  /// Wagon wheel: after a ball the bat hit for runs, ask where it went.
  /// Returns false when the scorer cancels the ball.
  Future<bool> _askShot(Delivery d) async {
    if (d.batRuns <= 0) return true; // wides, byes, leg-byes: no bat contact
    final batter = match.battingSide(_inn).nameOf(d.strikerId);
    final result = await showWagonWheel(
      context,
      batterName: batter,
      runs: d.batRuns,
    );
    if (result == null || !mounted) return false;
    final p = result.point;
    if (p != null) {
      d.shotX = p.dx;
      d.shotY = p.dy;
    }
    return true;
  }

  Future<void> _recordRuns(int runs) async {
    if (!canScore(_st)) return;
    final d = buildDelivery(
      _st,
      kind: _mode,
      runs: runs,
      runSource: _nbSource,
    );
    if (!await _askShot(d)) return;
    await _apply(d);
  }

  Future<void> _wicket() async {
    if (!canScore(_st)) return;
    final input = await showDialog<WicketInput>(
      context: context,
      builder: (_) => WicketDialog(
        mode: _mode,
        strikerId: _st.strikerId!,
        nonStrikerId: _st.nonStrikerId!,
        batting: match.battingSide(_inn),
        bowling: match.bowlingSide(_inn),
        freeHit: _st.freeHit,
      ),
    );
    if (input == null || !mounted) return;
    final d = buildDelivery(
      _st,
      kind: _mode,
      runs: input.runs,
      runSource: _nbSource,
      wicket: input.type,
      outId: input.outId,
      fielderId: input.fielderId,
      newBatterOnStrike: input.newBatterOnStrike,
    );
    if (!await _askShot(d)) return;
    await _apply(d);
  }

  Future<void> _undo() async {
    if (_inn.deliveries.isEmpty) return;
    final removed = _inn.deliveries.removeLast();
    _recompute();
    // If we are back at the start of an over, restore that over's bowler.
    if (_st.atOverStart) _inn.nextBowlerId = removed.bowlerId;
    _mode = DeliveryKind.normal;
    _nbSource = RunSource.bat;
    await _commit();
  }

  void _openScorecard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScorecardPage(match: match)),
    );
  }

  Future<void> _onMenu(String v) async {
    if (v == 'scorecard') {
      _openScorecard();
    } else if (v == 'end') {
      final ok = await confirm(
        context,
        title: 'End innings?',
        message:
            'Close this innings now (declaration, rain, time up)? You can resume it from the menu.',
        yes: 'End innings',
      );
      if (ok && mounted) {
        _inn.endedManually = true;
        await _commit();
      }
    } else if (v == 'resume') {
      _inn.endedManually = false;
      await _commit();
    } else if (v == 'reopen') {
      // Only offered while the 2nd innings has no balls yet.
      match.innings.removeLast();
      _firstDoneShown = true;
      await _commit();
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  List<int> get _runChoices {
    switch (_mode) {
      case DeliveryKind.normal:
        return const [0, 1, 2, 3, 4, 6];
      case DeliveryKind.wide:
        return const [0, 1, 2, 3, 4];
      case DeliveryKind.noBall:
        return const [0, 1, 2, 3, 4, 6];
      case DeliveryKind.bye:
      case DeliveryKind.legBye:
        return const [1, 2, 3, 4];
    }
  }

  String _runLabel(int r) {
    switch (_mode) {
      case DeliveryKind.normal:
        return r == 0 ? 'Dot' : '$r';
      case DeliveryKind.wide:
        return r == 0 ? 'Wide' : 'Wide +$r';
      case DeliveryKind.noBall:
        return r == 0 ? 'No-ball' : 'No-ball +$r';
      case DeliveryKind.bye:
        return 'Bye $r';
      case DeliveryKind.legBye:
        return 'Leg-bye $r';
    }
  }

  Widget _banner({
    required Widget icon,
    required String text,
    required String button,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTheme(
                  data: IconThemeData(color: cs.onTertiaryContainer),
                  child: icon,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: cs.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(InningsState st) {
    if (st.needsOpeners) {
      return _banner(
        icon: const Icon(Icons.flag),
        text: 'Select striker, non-striker and opening bowler to begin the innings.',
        button: 'Select players',
        onPressed: _openersDialog,
      );
    }
    if (st.needsNewBatter) {
      return _banner(
        icon: const CricketBatIcon(size: 22),
        text: 'Wicket! No batter selected yet. Please select the next batter.',
        button: 'Select batter',
        onPressed: _pickNewBatter,
      );
    }
    if (st.needsBowler) {
      return _banner(
        icon: const CricketBallIcon(size: 24),
        text: 'No bowler selected for over ${st.legalBalls ~/ 6 + 1}. '
            'Please select the bowler to continue.',
        button: 'Select bowler',
        onPressed: _pickBowler,
      );
    }
    if (st.complete) {
      if (_idx == 0 && match.innings.length == 1) {
        return _banner(
          icon: const Icon(Icons.flag),
          text: 'Innings complete (${st.completeReason}). '
              'Target for ${st.bowlingTeamName}: ${st.runs + 1}.',
          button: 'Start second innings',
          onPressed: _startSecond,
        );
      }
      if (_idx == 1) {
        return _banner(
          icon: const Icon(Icons.emoji_events),
          text: matchResult(match)?.text ?? 'Innings complete',
          button: 'View scorecard',
          onPressed: _openScorecard,
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _scoreHeader(InningsState st) {
    final cs = Theme.of(context).colorScheme;
    final lines = <Widget>[
      Text(
        'Innings ${_idx + 1} - ${match.oversLimit} overs',
        style: TextStyle(color: cs.onPrimary),
      ),
      Text(
        st.battingTeamName,
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        '${st.runs}/${st.wickets}',
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 40,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        'Overs ${oversText(st.legalBalls)} / ${match.oversLimit}'
        '   Current run rate ${st.runRate.toStringAsFixed(2)}',
        style: TextStyle(color: cs.onPrimary),
      ),
      Text(
        'Extras ${st.extrasTotal}: wides ${st.wides}, no-balls ${st.noBalls}, '
        'byes ${st.byes}, leg-byes ${st.legByes}',
        style: TextStyle(color: cs.onPrimary),
      ),
    ];
    if (st.freeHit) {
      lines.add(Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD54F),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'FREE HIT - the batter can only be run out',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
        ),
      ));
    }
    if (st.target != null) {
      lines.add(Text(
        'Target ${st.target}: need ${st.runsNeeded} from ${st.ballsRemaining} balls'
        '   Required run rate ${st.requiredRate.toStringAsFixed(2)}',
        style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600),
      ));
    }
    return Card(
      color: cs.primary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      ),
    );
  }

  Widget _batterRow(String? id, bool onStrike, InningsState st) {
    if (id == null) {
      return const ListTile(dense: true, title: Text('- (waiting for next batter)'));
    }
    final b = st.batters[id];
    if (b == null) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      leading: onStrike
          ? const CricketBatIcon(size: 26)
          : const Icon(Icons.person_outline),
      title: Text(onStrike ? '${b.name} *' : b.name),
      subtitle: Text(
          'Fours ${b.fours}   Sixes ${b.sixes}   Strike rate ${b.balls == 0 ? '\u2014' : b.strikeRate.toStringAsFixed(1)}'),
      trailing: Text(
        '${b.runs} (${b.balls})',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _bowlerCard(InningsState st) {
    final id = st.currentBowlerId;
    final bowl = match.bowlingSide(_inn);
    final b = id == null ? null : st.bowlers[id];
    return Card(
      child: ListTile(
        leading: const CricketBallIcon(size: 28),
        title: Text(id == null ? '-' : bowl.nameOf(id)),
        subtitle: Text(b == null
            ? '0.0 of ${st.maxOversPerBowler} overs - 0 runs - 0 wickets'
            : '${b.overs} of ${st.maxOversPerBowler} overs - ${b.runs} runs - ${b.wickets} wickets'),
        trailing: Text(
          id == null ? '' : 'Bowler',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }

  /// One ball as a small box (like the over strip on Google).
  Widget _ballBox(Delivery? d, {double size = 36}) {
    final cs = Theme.of(context).colorScheme;
    if (d == null) {
      // a ball still to come
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
      );
    }
    Color bg;
    Color fg = Colors.black87;
    String label;
    if (d.isWicket) {
      bg = const Color(0xFFD32F2F);
      fg = Colors.white;
      label = (d.kind == DeliveryKind.normal && d.runs == 0) ? 'W' : d.chipLabel;
    } else if (d.kind != DeliveryKind.normal) {
      bg = const Color(0xFFFFF0B3); // extras
      label = d.chipLabel;
    } else if (d.runs >= 6) {
      bg = const Color(0xFFFFCCBC);
      label = '${d.runs}';
    } else if (d.runs == 4) {
      bg = const Color(0xFFC8E6C9);
      label = '${d.runs}';
    } else {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurface;
      label = '${d.runs}';
    }
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: label.length > 2 ? 12 : 15,
        ),
      ),
    );
  }

  /// Last over, the number of this over, then this over's balls.
  Widget _overCard(InningsState st) {
    final cs = Theme.of(context).colorScheme;
    final over = st.legalBalls ~/ 6 + 1;
    final legal = st.currentOver.where((d) => d.isLegal).length;
    final empty = st.complete ? 0 : (legal >= 6 ? 0 : 6 - legal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in st.previousOver) ...[
                _ballBox(d, size: 30),
                const SizedBox(width: 5),
              ],
              const SizedBox(width: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  ordinal(over),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1.5, height: 30, color: cs.outlineVariant),
              const SizedBox(width: 10),
              for (final d in st.currentOver) ...[
                _ballBox(d),
                const SizedBox(width: 5),
              ],
              for (var i = 0; i < empty; i++) ...[
                _ballBox(null),
                const SizedBox(width: 5),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pad(InningsState st) {
    final cs = Theme.of(context).colorScheme;
    final enabled = canScore(st);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Record delivery',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final k in DeliveryKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _mode == k,
                    onSelected: enabled ? (_) => setState(() => _mode = k) : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final r in _runChoices)
                  FilledButton.tonal(
                    onPressed: enabled ? () => _recordRuns(r) : null,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _runLabel(r),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (st.needsNewBatter)
              FilledButton.icon(
                onPressed: _pickNewBatter,
                icon: const CricketBatIcon(size: 22),
                label: const Text('No batter selected - tap to select batter'),
              )
            else if (st.needsBowler)
              FilledButton.icon(
                onPressed: _pickBowler,
                icon: const CricketBallIcon(size: 20),
                label: const Text('No bowler selected - tap to select bowler'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError,
                      ),
                      onPressed: enabled ? _wicket : null,
                      icon: const Icon(Icons.close),
                      label: const Text('Wicket'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _inn.deliveries.isEmpty ? null : _undo,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo ball'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${match.sides[0].name} vs ${match.sides[1].name}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Scorecard',
            onPressed: _openScorecard,
          ),
          PopupMenuButton<String>(
            onSelected: _onMenu,
            itemBuilder: (_) => [
              if (!st.complete)
                const PopupMenuItem(value: 'end', child: Text('End innings now')),
              if (_inn.endedManually)
                const PopupMenuItem(value: 'resume', child: Text('Resume innings')),
              if (_idx == 1 && _inn.deliveries.isEmpty)
                const PopupMenuItem(
                    value: 'reopen', child: Text('Back to first innings')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _scoreHeader(st),
          _statusBanner(st),
          if (!st.needsOpeners) ...[
            Card(
              child: Column(
                children: [
                  _batterRow(st.strikerId, true, st),
                  _batterRow(st.nonStrikerId, false, st),
                ],
              ),
            ),
            _bowlerCard(st),
            _overCard(st),
          ],
          _pad(st),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
