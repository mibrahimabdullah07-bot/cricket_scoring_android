import 'dart:math';

/// Practical minimum number of players a team needs before it may start a
/// match. Change this one constant to change the rule everywhere.
const int kMinPlayersPerTeam = 3;

/// A team can have at most this many players (a normal cricket XI).
const int kMaxPlayersPerTeam = 11;

/// Largest number of overs per innings the app accepts.
const int kMaxOvers = 100;

final Random _random = Random();

/// Unique id (time + random) used for teams, players and matches.
String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _random.nextInt(1 << 30).toRadixString(36);
  return '$t$r';
}

// ---------------------------------------------------------------------------
// Team / Player (reusable, saved locally)
// ---------------------------------------------------------------------------

class Player {
  const Player({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Player.fromJson(Map<String, dynamic> j) =>
      Player(id: j['id'] as String, name: j['name'] as String);
}

class Team {
  Team({required this.id, required this.name, List<Player>? players})
      : players = players ?? <Player>[];

  final String id;
  String name;
  final List<Player> players;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'players': players.map((p) => p.toJson()).toList(),
      };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as String,
        name: j['name'] as String,
        players: (j['players'] as List)
            .map((e) => Player.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A team as it plays ONE match: a snapshot of the name and the chosen
/// players. Because it is a copy, editing or deleting the saved team later
/// never corrupts old matches.
class MatchSide {
  MatchSide({
    required this.teamId,
    required this.name,
    required this.players,
  });

  final String teamId;

  /// Not final: when a saved team is renamed, old matches follow the change.
  String name;
  final List<Player> players;

  String nameOf(String? playerId) {
    if (playerId == null) return '-';
    for (final p in players) {
      if (p.id == playerId) return p.name;
    }
    return 'Unknown';
  }

  Map<String, dynamic> toJson() => {
        'teamId': teamId,
        'name': name,
        'players': players.map((p) => p.toJson()).toList(),
      };

  factory MatchSide.fromJson(Map<String, dynamic> j) => MatchSide(
        teamId: j['teamId'] as String,
        name: j['name'] as String,
        players: (j['players'] as List)
            .map((e) => Player.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Delivery-level record
// ---------------------------------------------------------------------------

enum DeliveryKind { normal, wide, noBall, bye, legBye }

/// Who the runs on a no-ball were scored off.
enum RunSource { bat, bye, legBye }

enum WicketType { bowled, caught, lbw, stumped, runOut, hitWicket }

extension DeliveryKindX on DeliveryKind {
  /// Only these deliveries count as one of the six balls of an over.
  bool get isLegal =>
      this == DeliveryKind.normal ||
      this == DeliveryKind.bye ||
      this == DeliveryKind.legBye;

  String get label => switch (this) {
        DeliveryKind.normal => 'Normal',
        DeliveryKind.wide => 'Wide',
        DeliveryKind.noBall => 'No-ball',
        DeliveryKind.bye => 'Bye',
        DeliveryKind.legBye => 'Leg-bye',
      };
}

extension WicketTypeX on WicketType {
  String get label => switch (this) {
        WicketType.bowled => 'Bowled',
        WicketType.caught => 'Caught',
        WicketType.lbw => 'Leg before wicket',
        WicketType.stumped => 'Stumped',
        WicketType.runOut => 'Run out',
        WicketType.hitWicket => 'Hit wicket',
      };

  /// Bowler credit: every dismissal except a run out counts as the bowler's
  /// wicket.
  bool get creditsBowler => this != WicketType.runOut;

  /// Which dismissals are possible on which kind of delivery.
  bool allowedOn(DeliveryKind kind) {
    switch (kind) {
      case DeliveryKind.normal:
        return true;
      case DeliveryKind.wide:
        return this == WicketType.stumped ||
            this == WicketType.runOut ||
            this == WicketType.hitWicket;
      case DeliveryKind.noBall:
      case DeliveryKind.bye:
      case DeliveryKind.legBye:
        return this == WicketType.runOut;
    }
  }
}

/// One delivery (ball event). The whole innings can be rebuilt by replaying
/// the list of deliveries, which is what makes Undo trivial and safe.
///
/// Meaning of [runs]:
///  * normal  - runs off the bat
///  * wide    - extra runs run in addition to the 1 wide penalty
///  * noBall  - runs scored on the no-ball (see [runSource]); +1 penalty
///  * bye / legBye - runs run
class Delivery {
  Delivery({
    required this.kind,
    this.runs = 0,
    this.runSource = RunSource.bat,
    this.wicket,
    this.outId,
    this.fielderId,
    this.newBatterId,
    this.newBatterOnStrike = true,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
  });

  final DeliveryKind kind;
  final int runs;
  final RunSource runSource;
  final WicketType? wicket;
  final String? outId;
  final String? fielderId;

  /// Filled in after the wicket, when the scorer picks the next batter.
  String? newBatterId;

  /// Wagon wheel: where the ball went after the bat (x, y from the pitch;
  /// the edge of the picture is distance 1). Null when it was not recorded.
  double? shotX;
  double? shotY;
  final bool newBatterOnStrike;

  final String strikerId;
  final String nonStrikerId;
  final String bowlerId;

  bool get isLegal => kind.isLegal;
  bool get isWicket => wicket != null;

  /// A wide is not a ball faced by the batter; everything else is.
  bool get ballFaced => kind != DeliveryKind.wide;

  int get batRuns => (kind == DeliveryKind.normal ||
          (kind == DeliveryKind.noBall && runSource == RunSource.bat))
      ? runs
      : 0;
  int get wides => kind == DeliveryKind.wide ? 1 + runs : 0;
  int get noBalls => kind == DeliveryKind.noBall ? 1 : 0;
  int get byes => (kind == DeliveryKind.bye ||
          (kind == DeliveryKind.noBall && runSource == RunSource.bye))
      ? runs
      : 0;
  int get legByes => (kind == DeliveryKind.legBye ||
          (kind == DeliveryKind.noBall && runSource == RunSource.legBye))
      ? runs
      : 0;

  int get extras => wides + noBalls + byes + legByes;
  int get total => batRuns + extras;

  /// Runs charged to the bowler: bat runs, wides and no-balls only.
  /// Byes and leg-byes are NOT charged to the bowler.
  int get bowlerRuns => batRuns + wides + noBalls;

  /// Label for the "this over" chips, written in full words.
  String get chipLabel {
    final suffix = runSource == RunSource.bye
        ? ' byes'
        : runSource == RunSource.legBye
            ? ' leg-byes'
            : '';
    final base = switch (kind) {
      DeliveryKind.normal => runs == 0 ? '\u2022' : '$runs',
      DeliveryKind.wide => runs == 0 ? 'Wide' : 'Wide + $runs',
      DeliveryKind.noBall => runs == 0 ? 'No-ball' : 'No-ball + $runs$suffix',
      DeliveryKind.bye => 'Bye $runs',
      DeliveryKind.legBye => 'Leg-bye $runs',
    };
    if (!isWicket) return base;
    if (kind == DeliveryKind.normal && runs == 0) return 'Wicket';
    return '$base + Wicket';
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'runs': runs,
        'runSource': runSource.name,
        'wicket': wicket?.name,
        'outId': outId,
        'fielderId': fielderId,
        'newBatterId': newBatterId,
        'shotX': shotX,
        'shotY': shotY,
        'newBatterOnStrike': newBatterOnStrike,
        'strikerId': strikerId,
        'nonStrikerId': nonStrikerId,
        'bowlerId': bowlerId,
      };

  factory Delivery.fromJson(Map<String, dynamic> j) {
    final d = Delivery(
        kind: DeliveryKind.values.byName(j['kind'] as String),
        runs: j['runs'] as int,
        runSource: RunSource.values.byName(j['runSource'] as String),
        wicket: j['wicket'] == null
            ? null
            : WicketType.values.byName(j['wicket'] as String),
        outId: j['outId'] as String?,
        fielderId: j['fielderId'] as String?,
        newBatterId: j['newBatterId'] as String?,
        newBatterOnStrike: (j['newBatterOnStrike'] as bool?) ?? true,
        strikerId: j['strikerId'] as String,
        nonStrikerId: j['nonStrikerId'] as String,
        bowlerId: j['bowlerId'] as String,
    );
    d.shotX = (j['shotX'] as num?)?.toDouble();
    d.shotY = (j['shotY'] as num?)?.toDouble();
    return d;
  }
}

// ---------------------------------------------------------------------------
// Innings / Match
// ---------------------------------------------------------------------------

class Innings {
  Innings({
    required this.battingIndex,
    this.openStrikerId,
    this.openNonStrikerId,
    this.nextBowlerId,
    this.endedManually = false,
    this.isSuperOver = false,
    List<Delivery>? deliveries,
  }) : deliveries = deliveries ?? <Delivery>[];

  /// Index (0 or 1) into [CricketMatch.sides] of the batting side.
  final int battingIndex;

  String? openStrikerId;
  String? openNonStrikerId;

  /// Bowler chosen for the next delivery. Only used at the start of an over;
  /// mid-over the bowler is whoever bowled the previous ball.
  String? nextBowlerId;

  bool endedManually;

  /// A Super Over innings (one over, two wickets) that decides a tied match.
  final bool isSuperOver;
  final List<Delivery> deliveries;

  Map<String, dynamic> toJson() => {
        'battingIndex': battingIndex,
        'openStrikerId': openStrikerId,
        'openNonStrikerId': openNonStrikerId,
        'nextBowlerId': nextBowlerId,
        'endedManually': endedManually,
        'isSuperOver': isSuperOver,
        'deliveries': deliveries.map((d) => d.toJson()).toList(),
      };

  factory Innings.fromJson(Map<String, dynamic> j) => Innings(
        battingIndex: j['battingIndex'] as int,
        openStrikerId: j['openStrikerId'] as String?,
        openNonStrikerId: j['openNonStrikerId'] as String?,
        nextBowlerId: j['nextBowlerId'] as String?,
        endedManually: (j['endedManually'] as bool?) ?? false,
        isSuperOver: (j['isSuperOver'] as bool?) ?? false,
        deliveries: (j['deliveries'] as List)
            .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CricketMatch {
  CricketMatch({
    required this.id,
    required this.venue,
    required this.date,
    required this.createdAt,
    required this.oversLimit,
    required this.sides,
    required this.innings,
    this.tieAccepted = false,
  });

  final String id;
  final String venue;
  final DateTime date;
  final DateTime createdAt;
  final int oversLimit;
  final List<MatchSide> sides;
  final List<Innings> innings;

  /// The scorer chose to keep a tied match as a tie (no Super Over).
  bool tieAccepted;

  MatchSide battingSide(Innings i) => sides[i.battingIndex];
  MatchSide bowlingSide(Innings i) => sides[1 - i.battingIndex];

  Map<String, dynamic> toJson() => {
        'id': id,
        'venue': venue,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'oversLimit': oversLimit,
        'sides': sides.map((s) => s.toJson()).toList(),
        'innings': innings.map((i) => i.toJson()).toList(),
        'tieAccepted': tieAccepted,
      };

  factory CricketMatch.fromJson(Map<String, dynamic> j) => CricketMatch(
        id: j['id'] as String,
        venue: j['venue'] as String,
        date: DateTime.parse(j['date'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        oversLimit: j['oversLimit'] as int,
        sides: (j['sides'] as List)
            .map((e) => MatchSide.fromJson(e as Map<String, dynamic>))
            .toList(),
        innings: (j['innings'] as List)
            .map((e) => Innings.fromJson(e as Map<String, dynamic>))
            .toList(),
        tieAccepted: (j['tieAccepted'] as bool?) ?? false,
      );
}
