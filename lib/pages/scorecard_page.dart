import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine.dart';
import '../models.dart';
import '../team_logo.dart';

/// Match centre: a dark header, then the graph and each innings in its own
/// section. Used live (from the scoring screen) and for finished matches.
class ScorecardPage extends StatefulWidget {
  const ScorecardPage({super.key, required this.match});

  final CricketMatch match;

  @override
  State<ScorecardPage> createState() => _ScorecardPageState();
}

class _ScorecardPageState extends State<ScorecardPage> {
  int _tab = 0; // 0 = graph, 1 = first innings, 2 = second innings

  CricketMatch get match => widget.match;

  Widget _inningsTab(int i) {
    if (i >= match.innings.length) {
      return const Card(
        child: ListTile(title: Text('The second innings has not started yet.')),
      );
    }
    final name = match.sides[match.innings[i].battingIndex].name;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              TeamLogo(name: name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      i == 0 ? '1st innings' : '2nd innings',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _InningsCard(match: match, index: i),
      ],
    );
  }

  Widget _content() {
    if (_tab == 0) return _ProgressChart(match: match);
    return _inningsTab(_tab - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scorecard'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onSelected: (choice) async {
              final full = choice == 'full';
              await Clipboard.setData(ClipboardData(
                text: full ? scorecardText(match) : scoreSummaryText(match),
              ));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      full ? 'Full scorecard copied' : 'Short summary copied'),
                ),
              );
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'summary',
                child: Text('Copy short summary'),
              ),
              PopupMenuItem(
                value: 'full',
                child: Text('Copy full scorecard'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _MatchHeader(match: match),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.show_chart),
                  label: Text('Graph'),
                ),
                const ButtonSegment<int>(value: 1, label: Text('1st innings')),
                ButtonSegment<int>(
                  value: 2,
                  label: const Text('2nd innings'),
                  enabled: match.innings.length >= 2,
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(key: ValueKey(_tab), child: _content()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dark "match centre" header
// ---------------------------------------------------------------------------

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.match});

  final CricketMatch match;

  String get _format {
    final o = match.oversLimit;
    if (o == 10) return 'T10';
    if (o == 20) return 'T20';
    if (o == 50) return 'ODI';
    return '$o OVERS';
  }

  /// Score and overs of one side.
  List<String> _figures(int side) {
    for (var i = 0; i < match.innings.length; i++) {
      if (match.innings[i].battingIndex != side) continue;
      final st = computeInnings(match, i);
      if (st.needsOpeners) return ['\u2014', 'Yet to bat'];
      return [
        '${st.runs}/${st.wickets}',
        '${oversText(st.legalBalls)} overs',
      ];
    }
    return ['\u2014', 'Yet to bat'];
  }

  Widget _team(int side, String label) {
    final name = match.sides[side].name;
    final f = _figures(side);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TeamLogo(name: name, size: 72),
          const SizedBox(height: 12),
          Text(
            name.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            f[0],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            f[1],
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _result() {
    final result = matchResult(match);
    String headline;
    String sub;
    Color color;
    if (result != null) {
      final w = result.winnerIndex;
      if (w == null) {
        headline = 'MATCH TIED';
        sub = 'Scores are level';
        color = const Color(0xFFFFD54F);
      } else {
        final name = match.sides[w].name;
        headline = '${name.toUpperCase()} WON';
        var margin = result.text;
        if (margin.startsWith(name)) margin = margin.substring(name.length).trim();
        if (margin.startsWith('won by ')) margin = margin.substring(7);
        sub = 'By $margin';
        color = const Color(0xFF69F0AE);
      }
    } else {
      final i = match.innings.length - 1;
      final st = computeInnings(match, i);
      if (st.needsOpeners) {
        headline = 'MATCH IN PROGRESS';
        sub = '${st.battingTeamName} to bat';
      } else if (st.target != null) {
        headline = '${st.battingTeamName.toUpperCase()} NEED ${st.runsNeeded}';
        sub = 'runs from ${st.ballsRemaining} balls';
      } else if (st.complete && match.innings.length == 1) {
        headline = 'INNINGS BREAK';
        sub = 'Target ${st.runs + 1}';
      } else {
        headline = 'MATCH IN PROGRESS';
        sub = '${st.battingTeamName} are batting';
      }
      color = const Color(0xFFFFB74D);
    }
    return Column(
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final finished = isMatchComplete(match);
    final pill =
        finished ? const Color(0xFF4CD964) : const Color(0xFFFFB74D);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2B), Color(0xFF152A44)],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: pill.withAlpha(45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  finished ? 'MATCH COMPLETED' : 'MATCH IN PROGRESS',
                  style: TextStyle(
                    color: pill,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_format \u00B7 ${match.venue.toUpperCase()}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'MATCH CENTRE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatDate(match.date),
            style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            // left column: the team that batted first; right column: second
            children: [
              _team(match.innings[0].battingIndex, '1ST INNINGS'),
              _team(1 - match.innings[0].battingIndex, '2ND INNINGS'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0x33FFFFFF), height: 1),
          const SizedBox(height: 16),
          _result(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One innings: batters, extras and bowlers
// ---------------------------------------------------------------------------

class _InningsCard extends StatelessWidget {
  const _InningsCard({required this.match, required this.index});

  final CricketMatch match;
  final int index;

  static const double _nameWidth = 170;
  static const double _numWidth = 66;

  Widget _row(
    BuildContext context,
    List<String> cells, {
    bool header = false,
    String? sub,
  }) {
    final weight = header ? FontWeight.bold : FontWeight.normal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _nameWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cells.first, style: TextStyle(fontWeight: weight)),
                if (sub != null)
                  Text(sub, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          for (final c in cells.skip(1))
            SizedBox(
              width: _numWidth,
              child: Text(
                c,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: weight),
              ),
            ),
        ],
      ),
    );
  }

  /// Runs off the bat, then the extras on their own, then the total.
  Widget _totalsBox(BuildContext context, InningsState st) {
    final cs = Theme.of(context).colorScheme;
    Widget line(
      String label,
      String value, {
      bool bold = false,
      bool small = false,
      double indent = 0,
    }) {
      final style = TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
        fontSize: small ? 13 : (bold ? 16 : 14),
        color: small ? cs.onSurfaceVariant : null,
      );
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(value, style: style),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line('Runs off the bat', '${st.batRuns}', bold: true),
          const Divider(height: 16),
          Text(
            'EXTRAS',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(letterSpacing: 1.4),
          ),
          line('Byes', '${st.byes}', small: true, indent: 12),
          line('Leg-byes', '${st.legByes}', small: true, indent: 12),
          line('Wides', '${st.wides}', small: true, indent: 12),
          line('No-balls', '${st.noBalls}', small: true, indent: 12),
          line('Total extras', '${st.extrasTotal}', bold: true),
          const Divider(height: 16),
          line(
            'Total (${st.wickets} wickets, ${oversText(st.legalBalls)} overs)',
            '${st.runs}',
            bold: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = computeInnings(match, index);
    final bat = match.battingSide(match.innings[index]);
    final title = Theme.of(context).textTheme.titleMedium;

    if (st.needsOpeners) {
      return Card(
        child: ListTile(
          title: Text('Innings ${index + 1}: ${st.battingTeamName}'),
          subtitle: const Text('Innings not started yet'),
        ),
      );
    }

    final yetToBat =
        bat.players.where((p) => !st.batters.containsKey(p.id)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${st.battingTeamName}  ${st.runs}/${st.wickets}  '
              '(${oversText(st.legalBalls)} overs)',
              style: title?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Run rate ${st.runRate.toStringAsFixed(2)}'
              '${st.target != null ? '   Target ${st.target}' : ''}'
              '${st.complete ? '   (${st.completeReason})' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(
                    context,
                    const ['Batter', 'Runs', 'Balls', 'Ones', 'Twos', 'Threes', 'Fours', 'Sixes', 'Strike rate'],
                    header: true,
                  ),
                  const Divider(height: 1),
                  for (final b in st.batters.values)
                    _row(
                      context,
                      [
                        b.name,
                        '${b.runs}',
                        '${b.balls}',
                        '${b.ones}',
                        '${b.twos}',
                        '${b.threes}',
                        '${b.fours}',
                        '${b.sixes}',
                        b.balls == 0 ? '\u2014' : b.strikeRate.toStringAsFixed(1),
                      ],
                      sub: b.dismissal,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _totalsBox(context, st),
            if (yetToBat.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Did not bat: ${yetToBat.map((p) => p.name).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (st.fallOfWickets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Fall of wickets: ${st.fallOfWickets.map((f) => '${f.number}-${f.score} (${f.batterName}, ${f.overs} overs)').join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(
                    context,
                    const ['Bowler', 'Overs', 'Runs', 'Wickets', 'Economy', 'Wides', 'No-balls'],
                    header: true,
                  ),
                  const Divider(height: 1),
                  for (final b in st.bowlers.values)
                    _row(context, [
                      b.name,
                      b.overs,
                      '${b.runs}',
                      '${b.wickets}',
                      b.balls == 0 ? '\u2014' : b.economy.toStringAsFixed(1),
                      '${b.wides}',
                      '${b.noBalls}',
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match progress chart: both teams' runs against overs (live or finished)
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Match progress: both teams' runs ball by ball (live or finished)
// ---------------------------------------------------------------------------

const double _chartLeft = 40.0;
const double _chartRight = 12.0;

String _plural(int n, String word) => n == 1 ? '1 $word' : '$n ${word}s';

String _describeDelivery(Delivery d) {
  if (d.isWicket) {
    return d.runs > 0 ? 'Wicket (${_plural(d.runs, 'run')} first)' : 'Wicket';
  }
  switch (d.kind) {
    case DeliveryKind.normal:
      if (d.runs == 0) return 'Dot ball';
      if (d.runs == 4) return 'FOUR';
      if (d.runs == 6) return 'SIX';
      return _plural(d.runs, 'run');
    case DeliveryKind.wide:
      return d.runs == 0 ? 'Wide' : 'Wide +${d.runs}';
    case DeliveryKind.noBall:
      return d.runs == 0 ? 'No-ball' : 'No-ball +${d.runs}';
    case DeliveryKind.bye:
      return 'Bye ${d.runs}';
    case DeliveryKind.legBye:
      return 'Leg-bye ${d.runs}';
  }
}

class _ChartLine {
  _ChartLine({
    required this.name,
    required this.color,
    required this.steps,
    required this.total,
    required this.wickets,
    required this.finished,
    required this.batting,
    required this.bowling,
  }) {
    for (final s in steps) {
      byBall[s.ball] = s; // the last step of a ball wins
    }
  }

  final String name;
  final Color color;
  final List<BallStep> steps;
  final int total;
  final int wickets;
  final bool finished;
  final MatchSide batting;
  final MatchSide bowling;
  final Map<int, BallStep> byBall = <int, BallStep>{};

  int get lastBall => steps.isEmpty ? 0 : steps.last.ball;
}

class _ChartData {
  const _ChartData(this.lines, this.target);

  final List<_ChartLine> lines;
  final int? target;
}

class _ProgressChart extends StatefulWidget {
  const _ProgressChart({required this.match});

  final CricketMatch match;

  @override
  State<_ProgressChart> createState() => _ProgressChartState();
}

class _ProgressChartState extends State<_ProgressChart> {
  int? _selected; // legal ball chosen by touching, dragging or replaying
  Timer? _timer;
  bool _playing = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  _ChartData _data() {
    final match = widget.match;
    const colors = [Color(0xFF2E7D32), Color(0xFFFF7043)];
    final lines = <_ChartLine>[];
    int? target;
    for (var i = 0; i < match.innings.length && i < 2; i++) {
      final st = computeInnings(match, i);
      if (st.needsOpeners) continue;
      lines.add(_ChartLine(
        name: st.battingTeamName,
        color: colors[i],
        steps: inningsBalls(match, i),
        total: st.runs,
        wickets: st.wickets,
        finished: st.complete,
        batting: match.battingSide(match.innings[i]),
        bowling: match.bowlingSide(match.innings[i]),
      ));
      if (i == 1) target = st.target;
    }
    return _ChartData(lines, target);
  }

  int _maxBall(_ChartData data) {
    var latest = 0;
    for (final l in data.lines) {
      if (l.lastBall > latest) latest = l.lastBall;
    }
    final cap = widget.match.oversLimit * 6;
    return latest > cap ? cap : latest;
  }

  void _stopPlaying() {
    _timer?.cancel();
    _playing = false;
  }

  void _select(double dx, double width) {
    final w = width - _chartLeft - _chartRight;
    final limit = widget.match.oversLimit * 6;
    var k = ((dx - _chartLeft) / w * limit).round();
    if (k < 1) k = 1;
    if (k > limit) k = limit;
    if (k != _selected || _playing) {
      setState(() {
        _stopPlaying();
        _selected = k;
      });
    }
  }

  void _togglePlay() {
    if (_playing) {
      setState(_stopPlaying);
      return;
    }
    final max = _maxBall(_data());
    if (max < 1) return;
    setState(() {
      _playing = true;
      _selected = 1;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 90), (t) {
      final next = (_selected ?? 0) + 1;
      if (!mounted) {
        t.cancel();
        return;
      }
      if (next > max) {
        t.cancel();
        setState(() => _playing = false);
        return;
      }
      setState(() => _selected = next);
    });
  }

  Widget _detail(BuildContext context, _ChartData data, int k) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'After ${oversText(k)} overs',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          for (final l in data.lines) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: l.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: _lineDetail(context, l, k),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lineDetail(BuildContext context, _ChartLine l, int k) {
    final text = Theme.of(context).textTheme;
    final s = l.byBall[k];
    if (s == null) {
      return Text(
        l.finished && k > l.lastBall
            ? 'Innings finished: ${l.total}/${l.wickets}'
            : 'Has not batted this far yet',
        style: text.bodyMedium,
      );
    }
    final d = s.last;
    final batter = l.batting.nameOf(d.strikerId);
    final bowler = l.bowling.nameOf(d.bowlerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s.totalRuns}/${s.totalWickets}  after ${oversText(k)} overs',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        Text(
          '$bowler to $batter: ${s.deliveries.map(_describeDelivery).join(', then ')}',
          style: text.bodyMedium,
        ),
        Text(
          'Extras so far: ${s.totalExtras} '
          '(wides ${s.wides}, no-balls ${s.noBalls}, '
          'byes ${s.byes}, leg-byes ${s.legByes})',
          style: text.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final cs = Theme.of(context).colorScheme;
    final data = _data();
    if (data.lines.isEmpty) {
      return const Card(
        child: ListTile(title: Text('The match has not started yet.')),
      );
    }
    var latest = _maxBall(data);
    if (latest < 1) latest = 1;
    final selected = _selected ?? latest;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Match progress',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _togglePlay,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  label: Text(_playing ? 'Pause' : 'Replay'),
                ),
              ],
            ),
            Text(
              'The line moves with every ball. Touch or drag along the chart, '
              'or press Replay, to see the score, wickets and extras ball by '
              'ball. Red dots are wickets.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final l in data.lines)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 5,
                        decoration: BoxDecoration(
                          color: l.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${l.name}  ${l.total}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _select(d.localPosition.dx, width),
                  onHorizontalDragStart: (d) =>
                      _select(d.localPosition.dx, width),
                  onHorizontalDragUpdate: (d) =>
                      _select(d.localPosition.dx, width),
                  child: SizedBox(
                    height: 230,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _ChartPainter(
                        lines: data.lines,
                        oversLimit: match.oversLimit,
                        target: data.target,
                        selectedBall: selected,
                        textColor: cs.onSurface,
                        gridColor: cs.outlineVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _detail(context, data, selected),
          ],
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.lines,
    required this.oversLimit,
    required this.target,
    required this.selectedBall,
    required this.textColor,
    required this.gridColor,
  });

  final List<_ChartLine> lines;
  final int oversLimit;
  final int? target;
  final int selectedBall;
  final Color textColor;
  final Color gridColor;

  void _text(Canvas canvas, String text, Offset anchor,
      {bool alignRight = false, bool centered = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = anchor.dx;
    if (alignRight) {
      dx -= tp.width;
    } else if (centered) {
      dx -= tp.width / 2;
    }
    tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = _chartLeft;
    const right = _chartRight;
    const top = 10.0;
    const bottom = 30.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;

    var maxRuns = 10;
    for (final l in lines) {
      if (l.total > maxRuns) maxRuns = l.total;
    }
    final t = target;
    if (t != null && t > maxRuns) maxRuns = t;
    final yStep =
        maxRuns <= 50 ? 10 : (maxRuns <= 100 ? 20 : (maxRuns <= 200 ? 50 : 100));
    final yMax = ((maxRuns + yStep - 1) ~/ yStep) * yStep;
    final xStep =
        oversLimit <= 10 ? 2 : (oversLimit <= 20 ? 5 : (oversLimit <= 50 ? 10 : 20));

    double px(double overs) => left + w * (overs / oversLimit);
    double py(num runs) => top + h * (1 - runs / yMax);

    // grid and labels
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var y = 0; y <= yMax; y += yStep) {
      canvas.drawLine(Offset(left, py(y)), Offset(left + w, py(y)), grid);
      _text(canvas, '$y', Offset(left - 6, py(y)), alignRight: true);
    }
    for (var x = 0; x <= oversLimit; x += xStep) {
      _text(canvas, '$x', Offset(px(x.toDouble()), top + h + 14), centered: true);
    }
    _text(canvas, 'Overs', Offset(left + w / 2, top + h + 26), centered: true);

    // target of the chasing team
    if (t != null) {
      final dash = Paint()
        ..color = textColor.withAlpha(150)
        ..strokeWidth = 1.5;
      for (var x = left; x < left + w; x += 9) {
        canvas.drawLine(Offset(x, py(t)), Offset(x + 4, py(t)), dash);
      }
      _text(canvas, 'Target $t', Offset(left + w, py(t) - 9), alignRight: true);
    }

    // the chosen ball: a vertical marker
    final markerX = px(selectedBall / 6);
    canvas.drawLine(
      Offset(markerX, top),
      Offset(markerX, top + h),
      Paint()
        ..color = textColor.withAlpha(110)
        ..strokeWidth = 1.5,
    );

    for (final l in lines) {
      // one point for every ball
      final path = Path()..moveTo(px(0), py(0));
      for (final s in l.steps) {
        path.lineTo(px(s.ball / 6), py(s.totalRuns));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      for (final s in l.steps) {
        if (!s.wicket) continue;
        final o = Offset(px(s.ball / 6), py(s.totalRuns));
        canvas.drawCircle(o, 5, Paint()..color = const Color(0xFFD32F2F));
        canvas.drawCircle(
          o,
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      if (l.steps.isNotEmpty) {
        final end = l.steps.last;
        canvas.drawCircle(
          Offset(px(end.ball / 6), py(end.totalRuns)),
          4.5,
          Paint()..color = l.color,
        );
      }

      // where this team stood at the chosen ball
      final at = l.byBall[selectedBall];
      if (at != null) {
        final o = Offset(px(selectedBall / 6), py(at.totalRuns));
        canvas.drawCircle(o, 7, Paint()..color = l.color);
        canvas.drawCircle(
          o,
          7,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
