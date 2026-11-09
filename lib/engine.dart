import 'models.dart';

/// Cricket over notation: 15 legal balls -> "2.3".
/// 1 -> 1st, 2 -> 2nd, 3 -> 3rd, 11 -> 11th, 35 -> 35th ...
String ordinal(int n) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String oversText(int legalBalls) => '${legalBalls ~/ 6}.${legalBalls % 6}';

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

// ---------------------------------------------------------------------------
// Derived statistics (never stored - always rebuilt from the deliveries)
// ---------------------------------------------------------------------------

class BatterLine {
  BatterLine(this.id, this.name);

  final String id;
  final String name;
  int runs = 0;
  int balls = 0;
  int ones = 0;
  int twos = 0;
  int threes = 0;
  int fours = 0;
  int sixes = 0;
  bool out = false;
  String dismissal = 'not out';

  double get strikeRate => balls == 0 ? 0.0 : runs * 100 / balls;
}

class BowlerLine {
  BowlerLine(this.id, this.name);

  final String id;
  final String name;
  int balls = 0; // legal balls only
  int runs = 0; // runs conceded (no byes / leg-byes)
  int wickets = 0;
  int wides = 0;
  int noBalls = 0;

  String get overs => oversText(balls);
  double get economy => balls == 0 ? 0.0 : runs * 6 / balls;
}

class FallOfWicket {
  const FallOfWicket({
    required this.number,
    required this.score,
    required this.batterName,
    required this.overs,
  });

  final int number;
  final int score;
  final String batterName;
  final String overs;
}

class InningsState {
  InningsState({
    required this.maxWickets,
    required this.oversLimit,
    this.target,
  });

  final int maxWickets;
  final int oversLimit;
  final int? target;

  String battingTeamName = '';
  String bowlingTeamName = '';

  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;

  /// Runs scored off the bat (all batters added together). The innings total
  /// is always: runs off the bat + extras.
  int batRuns = 0;

  /// ICC free hit: the delivery after a no-ball. The batter can only be run out.
  bool freeHit = false;

  /// Most overs one bowler may bowl in this innings (see [calcMaxOversPerBowler]).
  int maxOversPerBowler = 0;

  /// Insertion-ordered: batting order.
  final Map<String, BatterLine> batters = <String, BatterLine>{};
  final Map<String, BowlerLine> bowlers = <String, BowlerLine>{};
  final List<FallOfWicket> fallOfWickets = <FallOfWicket>[];

  /// Deliveries of the over in progress (empty right after an over ends).
  List<Delivery> currentOver = <Delivery>[];

  /// Deliveries of the last completed over (empty before the first over ends).
  List<Delivery> previousOver = <Delivery>[];

  String? strikerId;
  String? nonStrikerId;
  String? currentBowlerId;
  String? lastOverBowlerId;

  bool needsOpeners = false;
  bool needsNewBatter = false;
  bool needsBowler = false;
  bool atOverStart = true;

  bool complete = false;
  String completeReason = '';

  int get extrasTotal => wides + noBalls + byes + legByes;

  int get ballsRemaining {
    final r = oversLimit * 6 - legalBalls;
    return r < 0 ? 0 : r;
  }

  int get runsNeeded {
    final t = target;
    if (t == null) return 0;
    final r = t - runs;
    return r < 0 ? 0 : r;
  }

  double get runRate => legalBalls == 0 ? 0.0 : runs * 6 / legalBalls;
  double get requiredRate =>
      ballsRemaining == 0 ? 0.0 : runsNeeded * 6 / ballsRemaining;
}

String _dismissal(Delivery d, MatchSide bowling) {
  final b = bowling.nameOf(d.bowlerId);
  final fielder = d.fielderId == null ? null : bowling.nameOf(d.fielderId);
  return switch (d.wicket!) {
    WicketType.bowled => 'bowled by $b',
    WicketType.lbw => 'leg before wicket, bowled by $b',
    WicketType.hitWicket => 'hit wicket, bowled by $b',
    WicketType.caught => fielder == null
        ? 'caught, bowled by $b'
        : (d.fielderId == d.bowlerId
            ? 'caught and bowled by $b'
            : 'caught by $fielder, bowled by $b'),
    WicketType.stumped => fielder == null
        ? 'stumped, bowled by $b'
        : 'stumped by $fielder, bowled by $b',
    WicketType.runOut => fielder == null ? 'run out' : 'run out ($fielder)',
  };
}

/// ICC rule: one bowler may bowl at most one fifth of the overs of an innings,
/// rounded up. That is 4 overs in a T20, 10 in a 50-over match and 2 in a T10.
/// For a very small team the limit is raised just enough for the innings to be
/// finishable (for example 3 players in a 20-over match need 7 overs each).
int calcMaxOversPerBowler(int oversLimit, int bowlingPlayers) {
  final fifth = (oversLimit + 4) ~/ 5;
  if (bowlingPlayers <= 0) return fifth;
  final needed = (oversLimit + bowlingPlayers - 1) ~/ bowlingPlayers;
  return fifth > needed ? fifth : needed;
}

/// Rebuilds the full state of an innings by replaying every delivery.
///
/// This is the heart of the app. Because nothing but the delivery list is
/// stored, scores can never drift out of sync and Undo is just
/// "remove the last delivery and replay".
InningsState computeInnings(CricketMatch m, int index) {
  final inn = m.innings[index];
  final bat = m.sides[inn.battingIndex];
  final bowl = m.sides[1 - inn.battingIndex];
  final int? target = index == 1 ? computeInnings(m, 0).runs + 1 : null;

  final st = InningsState(
    maxWickets: bat.players.length - 1,
    oversLimit: m.oversLimit,
    target: target,
  );
  st.battingTeamName = bat.name;
  st.bowlingTeamName = bowl.name;
  st.maxOversPerBowler =
      calcMaxOversPerBowler(m.oversLimit, bowl.players.length);

  BatterLine lineFor(String id) =>
      st.batters.putIfAbsent(id, () => BatterLine(id, bat.nameOf(id)));
  BowlerLine bowlerFor(String id) =>
      st.bowlers.putIfAbsent(id, () => BowlerLine(id, bowl.nameOf(id)));

  String? striker = inn.openStrikerId;
  String? nonStriker = inn.openNonStrikerId;
  if (striker == null || nonStriker == null) {
    st.needsOpeners = true;
    return st;
  }
  lineFor(striker);
  lineFor(nonStriker);

  var overStart = 0;
  var prevStart = 0;
  var prevEnd = 0;
  var freeHitNext = false;
  for (var i = 0; i < inn.deliveries.length; i++) {
    final d = inn.deliveries[i];
    final wasFreeHit = freeHitNext;
    final facing = lineFor(d.strikerId);
    lineFor(d.nonStrikerId);
    final bowler = bowlerFor(d.bowlerId);

    // ---- team totals
    st.runs += d.total;
    st.batRuns += d.batRuns;
    st.wides += d.wides;
    st.noBalls += d.noBalls;
    st.byes += d.byes;
    st.legByes += d.legByes;
    if (d.isLegal) st.legalBalls++;

    // ---- batter figures
    if (d.ballFaced) facing.balls++;
    final br = d.batRuns;
    facing.runs += br;
    if (br == 1) {
      facing.ones++;
    } else if (br == 2) {
      facing.twos++;
    } else if (br == 3) {
      facing.threes++;
    } else if (br == 4) {
      facing.fours++;
    } else if (br == 6) {
      facing.sixes++;
    }

    // ---- bowler figures
    bowler.runs += d.bowlerRuns;
    bowler.wides += d.wides;
    bowler.noBalls += d.noBalls;
    if (d.isLegal) bowler.balls++;

    // ---- positions at the crease after this ball
    String? s = d.strikerId;
    String? n = d.nonStrikerId;
    if (d.runs.isOdd) {
      final t = s;
      s = n;
      n = t;
    }

    if (d.isWicket) {
      st.wickets++;
      final outId = d.outId ?? d.strikerId;
      final outLine = lineFor(outId);
      outLine.out = true;
      outLine.dismissal = _dismissal(d, bowl);
      if (d.wicket!.creditsBowler) bowler.wickets++;
      st.fallOfWickets.add(FallOfWicket(
        number: st.wickets,
        score: st.runs,
        batterName: outLine.name,
        overs: oversText(st.legalBalls),
      ));

      final survivor = (outId == s) ? n : s;
      final incoming = d.newBatterId;
      if (incoming != null) lineFor(incoming);
      if (d.newBatterOnStrike) {
        s = incoming;
        n = survivor;
      } else {
        s = survivor;
        n = incoming;
      }
    }

    // end of over: batters change ends
    if (d.isLegal && st.legalBalls % 6 == 0) {
      final t = s;
      s = n;
      n = t;
      prevStart = overStart;
      prevEnd = i + 1;
      overStart = i + 1;
    }

    striker = s;
    nonStriker = n;

    // A no-ball gives the next ball as a free hit. A wide bowled as a free hit
    // does not use it up, so the free hit carries on to the next ball.
    freeHitNext = d.kind == DeliveryKind.noBall ||
        (wasFreeHit && d.kind == DeliveryKind.wide);
  }

  st.strikerId = striker;
  st.nonStrikerId = nonStriker;

  // ---- innings completion
  final targetRuns = target;
  if (targetRuns != null && st.runs >= targetRuns) {
    st.complete = true;
    st.completeReason = 'Target reached';
  } else if (st.wickets >= st.maxWickets) {
    st.complete = true;
    st.completeReason = 'All out';
  } else if (st.legalBalls >= m.oversLimit * 6) {
    st.complete = true;
    st.completeReason = 'Overs completed';
  } else if (inn.endedManually) {
    st.complete = true;
    st.completeReason = 'Innings closed';
  }

  st.freeHit = freeHitNext && !st.complete;
  st.needsNewBatter = !st.complete && (striker == null || nonStriker == null);

  // ---- bowler for the next delivery
  final last = inn.deliveries.isEmpty ? null : inn.deliveries.last;
  st.atOverStart = last == null || (last.isLegal && st.legalBalls % 6 == 0);
  if (st.atOverStart) {
    st.currentBowlerId = inn.nextBowlerId;
    st.lastOverBowlerId = last?.bowlerId;
    st.needsBowler = !st.complete && inn.nextBowlerId == null;
  } else {
    st.currentBowlerId = last!.bowlerId;
  }

  st.currentOver = inn.deliveries.sublist(overStart);
  st.previousOver = prevEnd > prevStart
      ? inn.deliveries.sublist(prevStart, prevEnd)
      : <Delivery>[];
  return st;
}

/// A point on the "runs against overs" chart.
class ChartPoint {
  const ChartPoint(this.overs, this.runs, {this.wicket = false});

  /// Overs bowled so far, as a decimal (2.5 balls of an over = 0.8333...).
  final double overs;

  /// Team runs so far.
  final int runs;

  /// True when a wicket fell at this point.
  final bool wicket;
}

/// Points for the worm chart of one innings: the score at the end of every
/// over, a marker where each wicket fell, and the current score.
List<ChartPoint> inningsProgress(CricketMatch m, int index) {
  final inn = m.innings[index];
  final points = <ChartPoint>[const ChartPoint(0, 0)];
  var runs = 0;
  var legal = 0;
  for (final d in inn.deliveries) {
    runs += d.total;
    if (d.isLegal) legal++;
    final overs = legal / 6;
    if (d.isWicket) {
      points.add(ChartPoint(overs, runs, wicket: true));
    } else if (d.isLegal && legal % 6 == 0) {
      points.add(ChartPoint(overs, runs));
    }
  }
  final last = points.last;
  final endOvers = legal / 6;
  if (last.overs != endOvers || last.runs != runs) {
    points.add(ChartPoint(endOvers, runs));
  }
  return points;
}

/// What happened in one over of an innings (for the match progress chart).
class OverSummary {
  const OverSummary({
    required this.number,
    required this.balls,
    required this.runs,
    required this.wickets,
    required this.extras,
    required this.totalRuns,
    required this.totalWickets,
    required this.totalExtras,
    required this.wides,
    required this.noBalls,
    required this.byes,
    required this.legByes,
  });

  /// Over number, starting at 1.
  final int number;

  /// Legal balls bowled in this over (6 when the over is complete).
  final int balls;

  /// Runs, wickets and extras that happened inside this over.
  final int runs;
  final int wickets;
  final int extras;

  /// Team figures after this over.
  final int totalRuns;
  final int totalWickets;
  final int totalExtras;

  /// Extras so far, by type, after this over.
  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;

  bool get complete => balls >= 6;
}

/// Over-by-over summary of an innings. The last entry may be an over that is
/// still in progress.
List<OverSummary> inningsOvers(CricketMatch m, int index) {
  final overs = <OverSummary>[];
  var legal = 0;
  var totalRuns = 0;
  var totalWickets = 0;
  var totalExtras = 0;
  var wides = 0;
  var noBalls = 0;
  var byes = 0;
  var legByes = 0;
  var overRuns = 0;
  var overWickets = 0;
  var overExtras = 0;
  var overBalls = 0;
  var overStarted = false;

  void closeOver() {
    overs.add(OverSummary(
      number: overs.length + 1,
      balls: overBalls,
      runs: overRuns,
      wickets: overWickets,
      extras: overExtras,
      totalRuns: totalRuns,
      totalWickets: totalWickets,
      totalExtras: totalExtras,
      wides: wides,
      noBalls: noBalls,
      byes: byes,
      legByes: legByes,
    ));
    overRuns = 0;
    overWickets = 0;
    overExtras = 0;
    overBalls = 0;
    overStarted = false;
  }

  for (final d in m.innings[index].deliveries) {
    totalRuns += d.total;
    totalExtras += d.extras;
    wides += d.wides;
    noBalls += d.noBalls;
    byes += d.byes;
    legByes += d.legByes;
    overRuns += d.total;
    overExtras += d.extras;
    overStarted = true;
    if (d.isWicket) {
      totalWickets++;
      overWickets++;
    }
    if (d.isLegal) {
      legal++;
      overBalls++;
      if (legal % 6 == 0) closeOver();
    }
  }
  if (overStarted) closeOver();
  return overs;
}

/// The state of an innings after one ball (together with any wides or
/// no-balls bowled just before it). The match progress chart has one step for
/// every ball.
class BallStep {
  const BallStep({
    required this.ball,
    required this.deliveries,
    required this.totalRuns,
    required this.totalWickets,
    required this.totalExtras,
    required this.wides,
    required this.noBalls,
    required this.byes,
    required this.legByes,
  });

  /// Legal balls bowled up to and including this step.
  final int ball;

  /// The deliveries of this step: wides / no-balls first, the legal ball last.
  final List<Delivery> deliveries;

  /// Team figures after this step.
  final int totalRuns;
  final int totalWickets;
  final int totalExtras;
  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;

  bool get wicket => deliveries.any((d) => d.isWicket);
  Delivery get last => deliveries.last;
}

/// One [BallStep] for every legal ball of the innings (plus a final step when
/// wides / no-balls were bowled after the last legal ball).
List<BallStep> inningsBalls(CricketMatch m, int index) {
  final steps = <BallStep>[];
  var group = <Delivery>[];
  var legal = 0;
  var totalRuns = 0;
  var totalWickets = 0;
  var totalExtras = 0;
  var wides = 0;
  var noBalls = 0;
  var byes = 0;
  var legByes = 0;

  void closeStep() {
    steps.add(BallStep(
      ball: legal,
      deliveries: group,
      totalRuns: totalRuns,
      totalWickets: totalWickets,
      totalExtras: totalExtras,
      wides: wides,
      noBalls: noBalls,
      byes: byes,
      legByes: legByes,
    ));
    group = <Delivery>[];
  }

  for (final d in m.innings[index].deliveries) {
    group.add(d);
    totalRuns += d.total;
    totalExtras += d.extras;
    wides += d.wides;
    noBalls += d.noBalls;
    byes += d.byes;
    legByes += d.legByes;
    if (d.isWicket) totalWickets++;
    if (d.isLegal) {
      legal++;
      closeStep();
    }
  }
  if (group.isNotEmpty) closeStep();
  return steps;
}

/// True when the scorer may enter the next delivery.
bool canScore(InningsState st) =>
    !st.complete && !st.needsOpeners && !st.needsNewBatter && !st.needsBowler;

/// Creates a delivery for the current crease/bowler, applying the scoring
/// rules (wides/no-balls are not legal balls, wicket normalisation, etc.).
Delivery buildDelivery(
  InningsState st, {
  required DeliveryKind kind,
  int runs = 0,
  RunSource runSource = RunSource.bat,
  WicketType? wicket,
  String? outId,
  String? fielderId,
  bool? newBatterOnStrike,
}) {
  final striker = st.strikerId!;
  final nonStriker = st.nonStrikerId!;
  final bowler = st.currentBowlerId!;

  var k = kind;
  var r = runs;
  var src = runSource;

  // Only a run out can have runs completed on a wicket ball.
  if (wicket != null && wicket != WicketType.runOut) r = 0;
  // A bye / leg-bye of zero runs is just a dot ball.
  if ((k == DeliveryKind.bye || k == DeliveryKind.legBye) && r == 0) {
    k = DeliveryKind.normal;
  }
  if (k != DeliveryKind.noBall || r == 0) src = RunSource.bat;

  String? out;
  var onStrike = true;
  if (wicket != null) {
    out = wicket == WicketType.runOut ? (outId ?? striker) : striker;
    if (wicket == WicketType.runOut) {
      // Default: the new batter takes the end the dismissed batter was at.
      onStrike = newBatterOnStrike ?? ((out == striker) != r.isOdd);
    }
  }

  return Delivery(
    kind: k,
    runs: r,
    runSource: src,
    wicket: wicket,
    outId: out,
    fielderId: fielderId,
    newBatterOnStrike: onStrike,
    strikerId: striker,
    nonStrikerId: nonStriker,
    bowlerId: bowler,
  );
}

// ---------------------------------------------------------------------------
// Match result
// ---------------------------------------------------------------------------

class MatchResult {
  const MatchResult(this.text, this.winnerIndex);

  final String text;

  /// Index into CricketMatch.sides, or null for a tie.
  final int? winnerIndex;
}

bool isMatchComplete(CricketMatch m) =>
    m.innings.length == 2 &&
    computeInnings(m, 0).complete &&
    computeInnings(m, 1).complete;

MatchResult? matchResult(CricketMatch m) {
  if (!isMatchComplete(m)) return null;
  final a = computeInnings(m, 0);
  final b = computeInnings(m, 1);
  final second = m.battingSide(m.innings[1]);
  final first = m.battingSide(m.innings[0]);
  if (b.runs > a.runs) {
    final left = b.maxWickets - b.wickets;
    return MatchResult(
      '${second.name} won by $left wicket${left == 1 ? '' : 's'}',
      m.innings[1].battingIndex,
    );
  }
  if (b.runs < a.runs) {
    final diff = a.runs - b.runs;
    return MatchResult(
      '${first.name} won by $diff run${diff == 1 ? '' : 's'}',
      m.innings[0].battingIndex,
    );
  }
  return const MatchResult('Match tied', null);
}

String _wicketsText(int n) => n == 1 ? '1 wicket' : '$n wickets';

/// Full scorecard as neat plain text (for notes, email, WhatsApp...).
String scorecardText(CricketMatch m) {
  final b = StringBuffer();
  b.writeln('\u{1F3CF} ${m.sides[0].name} vs ${m.sides[1].name}');
  b.writeln('Venue: ${m.venue}');
  b.writeln('Date: ${formatDate(m.date)}');
  b.writeln('Format: ${m.oversLimit} overs per side');
  final r = matchResult(m);
  b.writeln(r != null ? '\u{1F3C6} Result: ${r.text}' : 'Result: match in progress');

  for (var i = 0; i < m.innings.length; i++) {
    final st = computeInnings(m, i);
    final bat = m.battingSide(m.innings[i]);
    b.writeln();
    b.writeln('------------------------------');
    if (st.needsOpeners) {
      b.writeln('${st.battingTeamName}: innings not started');
      continue;
    }
    b.writeln(
        '${i + 1}. ${st.battingTeamName.toUpperCase()}: ${st.runs}/${st.wickets} (${oversText(st.legalBalls)} overs)');
    if (st.target != null) b.writeln('Target: ${st.target}');

    b.writeln();
    b.writeln('BATTING');
    var n = 1;
    for (final bt in st.batters.values) {
      b.writeln('$n. ${bt.name}: ${bt.runs} runs from ${bt.balls} balls');
      b.writeln(
          '    Fours ${bt.fours}, Sixes ${bt.sixes}, Strike rate ${bt.balls == 0 ? '\u2014' : bt.strikeRate.toStringAsFixed(1)}');
      b.writeln('    ${bt.dismissal}');
      n++;
    }
    final didNotBat =
        bat.players.where((p) => !st.batters.containsKey(p.id)).toList();
    if (didNotBat.isNotEmpty) {
      b.writeln('Did not bat: ${didNotBat.map((p) => p.name).join(', ')}');
    }
    b.writeln('Runs off the bat: ${st.batRuns}');
    b.writeln(
        'Extras: ${st.extrasTotal} (byes ${st.byes}, leg-byes ${st.legByes}, wides ${st.wides}, no-balls ${st.noBalls})');
    b.writeln(
        'Total: ${st.runs} (${st.batRuns} off the bat + ${st.extrasTotal} extras)');
    if (st.fallOfWickets.isNotEmpty) {
      b.writeln('Fall of wickets: ${st.fallOfWickets.map((f) => '${f.number}-${f.score} (${f.batterName}, ${f.overs} overs)').join(', ')}');
    }

    b.writeln();
    b.writeln('BOWLING');
    for (final bw in st.bowlers.values) {
      b.writeln(
          '${bw.name}: ${bw.overs} overs, ${bw.runs} runs, ${_wicketsText(bw.wickets)} (economy ${bw.balls == 0 ? '\u2014' : bw.economy.toStringAsFixed(1)})');
    }
  }
  b.writeln();
  b.writeln('Scored with Cricket Scorer');
  return b.toString().trimRight();
}

/// Short, WhatsApp-friendly summary: scores, result, best batter and bowler.
String scoreSummaryText(CricketMatch m) {
  final b = StringBuffer();
  b.writeln('\u{1F3CF} ${m.sides[0].name} vs ${m.sides[1].name}');
  b.writeln('${m.venue} | ${formatDate(m.date)} | ${m.oversLimit} overs');
  b.writeln();

  BatterLine? bestBat;
  BowlerLine? bestBowl;
  for (var i = 0; i < m.innings.length; i++) {
    final st = computeInnings(m, i);
    if (st.needsOpeners) continue;
    b.writeln(
        '${st.battingTeamName}: ${st.runs}/${st.wickets} (${oversText(st.legalBalls)} overs)');
    for (final bt in st.batters.values) {
      final cur = bestBat;
      if (cur == null ||
          bt.runs > cur.runs ||
          (bt.runs == cur.runs && bt.balls < cur.balls)) {
        bestBat = bt;
      }
    }
    for (final bw in st.bowlers.values) {
      final cur = bestBowl;
      if (cur == null ||
          bw.wickets > cur.wickets ||
          (bw.wickets == cur.wickets && bw.runs < cur.runs)) {
        bestBowl = bw;
      }
    }
  }

  final r = matchResult(m);
  if (r != null) {
    b.writeln();
    b.writeln('\u{1F3C6} ${r.text}');
  }
  final bb = bestBat;
  if (bb != null && bb.runs > 0) {
    b.writeln('Top batter: ${bb.name} - ${bb.runs} runs from ${bb.balls} balls');
  }
  final bw = bestBowl;
  if (bw != null && bw.wickets > 0) {
    b.writeln(
        'Top bowler: ${bw.name} - ${_wicketsText(bw.wickets)} for ${bw.runs} runs (${bw.overs} overs)');
  }
  return b.toString().trimRight();
}
