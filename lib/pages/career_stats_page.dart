import 'package:flutter/material.dart';

import '../engine.dart';
import '../models.dart';
import '../store.dart';
import '../wagon_wheel.dart';
import '../widgets.dart';

/// A bowler needs at least one full over to be ranked on economy / average.
const int kMinBallsForEconomy = 6;

/// A batter needs at least two overs of balls faced to be ranked on strike rate.
const int kMinBallsForStrikeRate = 12;

const String _dash = '\u2014'; // shown when a value cannot be worked out

String _fmt(double? v) => v == null ? _dash : v.toStringAsFixed(1);

/// Career totals for one player, added up over all COMPLETED saved matches.
class CareerLine {
  CareerLine(this.id, this.name, this.team);

  final String id;
  String name;
  String team;
  int matches = 0;

  // batting
  int innings = 0;
  int notOuts = 0;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  int highScore = 0;
  bool highScoreNotOut = false;
  int fifties = 0;
  int hundreds = 0;
  int ducks = 0;

  /// Wagon wheel shots (only balls recorded with a direction).
  final List<WagonShot> shots = <WagonShot>[];

  // bowling
  int ballsBowled = 0;
  int runsConceded = 0;
  int wickets = 0;
  int wides = 0;
  int noBalls = 0;
  bool hasBestFigures = false;
  int bestWickets = 0;
  int bestRuns = 0;

  int get dismissals => innings - notOuts;

  double? get battingAverage => dismissals <= 0 ? null : runs / dismissals;
  double? get strikeRate => balls == 0 ? null : runs * 100 / balls;
  String get highestScoreText =>
      innings == 0 ? _dash : '$highScore${highScoreNotOut ? '*' : ''}';

  String get overs => oversText(ballsBowled);
  double? get economy =>
      ballsBowled == 0 ? null : runsConceded * 6 / ballsBowled;
  double? get bowlingAverage => wickets == 0 ? null : runsConceded / wickets;
  String get bestFiguresText =>
      hasBestFigures ? '$bestWickets/$bestRuns' : _dash;
}

/// Replays every completed match (the same engine used for live scoring)
/// and adds each player's figures together. A match that cannot be read is
/// skipped instead of crashing the screen.
Map<String, CareerLine> buildCareerStats(List<CricketMatch> matches) {
  final map = <String, CareerLine>{};
  for (final m in matches) {
    try {
      if (!isMatchComplete(m)) continue;
      final counted = <String>{};
      for (var i = 0; i < m.innings.length; i++) {
        if (m.innings[i].isSuperOver) continue; // Super Overs are not career figures
        final st = computeInnings(m, i);
        if (st.needsOpeners) continue;

        for (final b in st.batters.values) {
          if (b.balls == 0 && !b.out) continue; // waited at the crease only
          final c = map.putIfAbsent(
              b.id, () => CareerLine(b.id, b.name, st.battingTeamName));
          c.name = b.name;
          c.team = st.battingTeamName;
          if (counted.add(b.id)) c.matches++;
          c.innings++;
          if (!b.out) c.notOuts++;
          c.runs += b.runs;
          c.balls += b.balls;
          c.fours += b.fours;
          c.sixes += b.sixes;
          if (b.runs > c.highScore) {
            c.highScore = b.runs;
            c.highScoreNotOut = !b.out;
          }
          if (b.runs >= 100) {
            c.hundreds++;
          } else if (b.runs >= 50) {
            c.fifties++;
          }
          if (b.out && b.runs == 0) c.ducks++;
        }

        for (final bw in st.bowlers.values) {
          final c = map.putIfAbsent(
              bw.id, () => CareerLine(bw.id, bw.name, st.bowlingTeamName));
          c.name = bw.name;
          if (c.team.isEmpty) c.team = st.bowlingTeamName;
          if (counted.add(bw.id)) c.matches++;
          c.ballsBowled += bw.balls;
          c.runsConceded += bw.runs;
          c.wickets += bw.wickets;
          c.wides += bw.wides;
          c.noBalls += bw.noBalls;
          final better = !c.hasBestFigures ||
              bw.wickets > c.bestWickets ||
              (bw.wickets == c.bestWickets && bw.runs < c.bestRuns);
          if (bw.balls > 0 && better) {
            c.hasBestFigures = true;
            c.bestWickets = bw.wickets;
            c.bestRuns = bw.runs;
          }
        }

        // wagon wheel shots of this innings
        for (final d in m.innings[i].deliveries) {
          final x = d.shotX;
          final y = d.shotY;
          if (x == null || y == null || d.batRuns <= 0) continue;
          final owner = map[d.strikerId];
          if (owner != null) owner.shots.add(WagonShot(x, y, d.batRuns));
        }
      }
    } catch (e) {
      debugPrint('Skipping an unreadable match in the statistics: $e');
    }
  }
  return map;
}

// ---------------------------------------------------------------------------
// Top 3 helpers
// ---------------------------------------------------------------------------

const List<Color> _medal = [
  Color(0xFFFFD54F), // gold
  Color(0xFFCFD8DC), // silver
  Color(0xFFD7A86E), // bronze
];

/// Top 3 batters: most runs. Ties are split by average, then by name.
List<CareerLine> _topBatters(List<CareerLine> all) {
  final list = all.where((c) => c.runs > 0).toList();
  list.sort((a, b) {
    final runs = b.runs.compareTo(a.runs);
    if (runs != 0) return runs;
    final avg = (b.battingAverage ?? 0.0).compareTo(a.battingAverage ?? 0.0);
    if (avg != 0) return avg;
    return a.name.compareTo(b.name);
  });
  return list.take(3).toList();
}

/// Top 3 bowlers: most wickets. Ties are split by economy, then by name.
List<CareerLine> _topBowlers(List<CareerLine> all) {
  final list = all.where((c) => c.wickets > 0).toList();
  list.sort((a, b) {
    final wickets = b.wickets.compareTo(a.wickets);
    if (wickets != 0) return wickets;
    final econ = (a.economy ?? 999.0).compareTo(b.economy ?? 999.0);
    if (econ != 0) return econ;
    return a.name.compareTo(b.name);
  });
  return list.take(3).toList();
}

List<MapEntry<String, String>> _battingStats(CareerLine c) => [
      MapEntry('Matches', '${c.matches}'),
      MapEntry('Innings', '${c.innings}'),
      MapEntry('Not outs', '${c.notOuts}'),
      MapEntry('Highest score', c.highestScoreText),
      MapEntry('Average', _fmt(c.battingAverage)),
      MapEntry('Strike rate', _fmt(c.strikeRate)),
      MapEntry('Balls faced', '${c.balls}'),
      MapEntry('Fours', '${c.fours}'),
      MapEntry('Sixes', '${c.sixes}'),
      MapEntry('Fifties', '${c.fifties}'),
      MapEntry('Hundreds', '${c.hundreds}'),
      MapEntry('Ducks', '${c.ducks}'),
    ];

List<MapEntry<String, String>> _bowlingStats(CareerLine c) => [
      MapEntry('Matches', '${c.matches}'),
      MapEntry('Overs bowled', c.overs),
      MapEntry('Legal balls', '${c.ballsBowled}'),
      MapEntry('Runs conceded', '${c.runsConceded}'),
      MapEntry('Economy', _fmt(c.economy)),
      MapEntry('Average', _fmt(c.bowlingAverage)),
      MapEntry('Best figures', c.bestFiguresText),
      MapEntry('Wides', '${c.wides}'),
      MapEntry('No-balls', '${c.noBalls}'),
    ];

/// Small boxes: value on top, clear label underneath.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<MapEntry<String, String>> stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in stats)
              Container(
                width: w,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        e.value,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.key,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// One player: batting and bowling on separate tabs
// ---------------------------------------------------------------------------

class _PlayerPage extends StatelessWidget {
  const _PlayerPage({required this.line});

  final CareerLine line;

  Widget _tab(
    BuildContext context, {
    required bool played,
    required String emptyText,
    required String bigValue,
    required String bigLabel,
    required List<MapEntry<String, String>> stats,
    Widget? extra,
  }) {
    if (!played) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              Text(
                bigValue,
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
              Text(bigLabel, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _StatGrid(stats: stats),
        if (extra != null) ...[
          const SizedBox(height: 24),
          Text('Wagon wheel', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Where this batter hit the ball, from the pitch in the middle.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          extra,
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.name),
              Text(line.team, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: CricketBatIcon(size: 22), text: 'Batting'),
              Tab(icon: CricketBallIcon(size: 22), text: 'Bowling'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tab(
              context,
              played: line.innings > 0,
              emptyText: '${line.name} has not batted in a finished match yet.',
              bigValue: '${line.runs}',
              bigLabel: 'Total runs',
              stats: _battingStats(line),
              extra: WagonWheelView(shots: line.shots),
            ),
            _tab(
              context,
              played: line.ballsBowled > 0,
              emptyText: '${line.name} has not bowled in a finished match yet.',
              bigValue: '${line.wickets}',
              bigLabel: 'Total wickets',
              stats: _bowlingStats(line),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The statistics screen: "Top 3" and "By team"
// ---------------------------------------------------------------------------

class CareerStatsPage extends StatefulWidget {
  const CareerStatsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<CareerStatsPage> createState() => _CareerStatsPageState();
}

class _CareerStatsPageState extends State<CareerStatsPage> {
  int _view = 0; // 0 = Top 3, 1 = By team

  void _openPlayer(CareerLine c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PlayerPage(line: c)),
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _section({
    required Widget icon,
    required String title,
    required String note,
    required List<CareerLine> top,
    required String Function(CareerLine) value,
    required String unit,
    required String emptyText,
  }) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Text(note, style: theme.bodySmall),
            ),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(emptyText),
              ),
            for (var i = 0; i < top.length; i++)
              ListTile(
                onTap: () => _openPlayer(top[i]),
                leading: CircleAvatar(
                  backgroundColor: _medal[i],
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                title: Text(top[i].name),
                subtitle: Text(top[i].team),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value(top[i]),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                    Text(unit, style: theme.labelSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topView(List<CareerLine> lines) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section(
          icon: const CricketBatIcon(size: 28),
          title: 'Top 3 batters',
          note: 'Ranked by total runs',
          top: _topBatters(lines),
          value: (c) => '${c.runs}',
          unit: 'runs',
          emptyText: 'No batting figures yet. Finish a match to see them.',
        ),
        const SizedBox(height: 12),
        _section(
          icon: const CricketBallIcon(size: 28),
          title: 'Top 3 bowlers',
          note: 'Ranked by total wickets',
          top: _topBowlers(lines),
          value: (c) => '${c.wickets}',
          unit: 'wickets',
          emptyText: 'No wickets yet. Finish a match to see them.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
          child: Text(
            'Tap a player to see full batting and bowling figures. '
            'Players with equal totals are ordered by average (batters) or '
            'economy (bowlers).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _teamsView(List<CareerLine> lines) {
    final byTeam = <String, List<CareerLine>>{};
    for (final c in lines) {
      if (c.innings == 0 && c.ballsBowled == 0) continue;
      byTeam.putIfAbsent(c.team, () => <CareerLine>[]).add(c);
    }
    final teams = byTeam.keys.toList()..sort();
    if (teams.isEmpty) {
      return _empty('No player statistics yet.\nFinish a match to see them.');
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final team in teams)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(
                team,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${byTeam[team]!.length} players'),
              children: [
                for (final c in (byTeam[team]!
                  ..sort((a, b) => a.name.compareTo(b.name))))
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text('Runs ${c.runs}   |   Wickets ${c.wickets}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openPlayer(c),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player statistics')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final lines = buildCareerStats(widget.store.matches).values.toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.emoji_events),
                        label: Text('Top 3'),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.groups),
                        label: Text('By team'),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey(_view),
                    child: _view == 0 ? _topView(lines) : _teamsView(lines),
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
