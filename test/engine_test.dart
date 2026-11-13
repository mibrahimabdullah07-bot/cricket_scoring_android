import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scoring_app/engine.dart';
import 'package:cricket_scoring_app/models.dart';

/// Two sides (A1..An and B1..Bn). Team A bats first; A1 & A2 open, B1 bowls.
CricketMatch newMatch({int overs = 2, int players = 4}) {
  MatchSide side(String code) => MatchSide(
        teamId: code,
        name: 'Team $code',
        players: [
          for (var i = 1; i <= players; i++) Player(id: '$code$i', name: '$code$i'),
        ],
      );
  return CricketMatch(
    id: 'm1',
    venue: 'Test Ground',
    date: DateTime(2026, 11, 1),
    createdAt: DateTime(2026, 11, 1),
    oversLimit: overs,
    sides: [side('A'), side('B')],
    innings: [
      Innings(
        battingIndex: 0,
        openStrikerId: 'A1',
        openNonStrikerId: 'A2',
        nextBowlerId: 'B1',
      ),
    ],
  );
}

/// Records one delivery exactly the way the scoring screen does.
InningsState play(
  CricketMatch m, {
  int inningsIndex = 0,
  DeliveryKind kind = DeliveryKind.normal,
  int runs = 0,
  RunSource runSource = RunSource.bat,
  WicketType? wicket,
  String? outId,
}) {
  final inn = m.innings[inningsIndex];
  final st = computeInnings(m, inningsIndex);
  inn.deliveries.add(buildDelivery(
    st,
    kind: kind,
    runs: runs,
    runSource: runSource,
    wicket: wicket,
    outId: outId,
  ));
  inn.nextBowlerId = null;
  return computeInnings(m, inningsIndex);
}

void main() {
  test('wide is not a legal ball and costs the bowler a run', () {
    final m = newMatch();
    final st = play(m, kind: DeliveryKind.wide);
    expect(st.runs, 1);
    expect(st.legalBalls, 0);
    expect(st.wides, 1);
    expect(st.bowlers['B1']!.runs, 1);
    expect(st.bowlers['B1']!.balls, 0);
    expect(st.batters['A1']!.balls, 0);
    expect(oversText(st.legalBalls), '0.0');
  });

  test('no-ball with a four: 5 runs, not a legal ball, batter faced it', () {
    final m = newMatch();
    final st = play(m, kind: DeliveryKind.noBall, runs: 4);
    expect(st.runs, 5);
    expect(st.legalBalls, 0);
    expect(st.noBalls, 1);
    expect(st.batters['A1']!.runs, 4);
    expect(st.batters['A1']!.balls, 1);
    expect(st.batters['A1']!.fours, 1);
    expect(st.bowlers['B1']!.runs, 5);
  });

  test('odd runs change the striker', () {
    final m = newMatch();
    final st = play(m, runs: 1);
    expect(st.strikerId, 'A2');
    expect(st.nonStrikerId, 'A1');
    expect(st.batters['A1']!.ones, 1);
  });

  test('bye: strike changes, ball faced, runs not charged to bowler', () {
    final m = newMatch();
    final st = play(m, kind: DeliveryKind.bye, runs: 1);
    expect(st.runs, 1);
    expect(st.byes, 1);
    expect(st.batters['A1']!.runs, 0);
    expect(st.batters['A1']!.balls, 1);
    expect(st.bowlers['B1']!.runs, 0);
    expect(st.legalBalls, 1);
    expect(st.strikerId, 'A2');
  });

  test('six legal balls end the over: strike changes, new bowler required', () {
    final m = newMatch();
    var st = play(m);
    for (var i = 0; i < 5; i++) {
      st = play(m);
    }
    expect(oversText(st.legalBalls), '1.0');
    expect(st.atOverStart, isTrue);
    expect(st.needsBowler, isTrue);
    expect(st.strikerId, 'A2');
    expect(canScore(st), isFalse);
    expect(st.lastOverBowlerId, 'B1');

    m.innings[0].nextBowlerId = 'B2';
    st = computeInnings(m, 0);
    expect(st.needsBowler, isFalse);
    expect(st.currentBowlerId, 'B2');
    expect(canScore(st), isTrue);
  });

  test('a wide inside an over does not advance the over', () {
    final m = newMatch();
    play(m);
    play(m, kind: DeliveryKind.wide);
    final st = play(m);
    expect(st.legalBalls, 2);
    expect(st.currentOver.length, 3);
  });

  test('bowled: bowler credited, next batter required, new batter on strike', () {
    final m = newMatch();
    var st = play(m, wicket: WicketType.bowled);
    expect(st.wickets, 1);
    expect(st.bowlers['B1']!.wickets, 1);
    expect(st.batters['A1']!.out, isTrue);
    expect(st.batters['A1']!.dismissal, 'bowled by B1');
    expect(st.needsNewBatter, isTrue);
    expect(canScore(st), isFalse);

    m.innings[0].deliveries.last.newBatterId = 'A3';
    st = computeInnings(m, 0);
    expect(st.needsNewBatter, isFalse);
    expect(st.strikerId, 'A3');
    expect(st.nonStrikerId, 'A2');
  });

  test('run out: no bowler credit, runs counted, chosen batter out', () {
    final m = newMatch();
    var st = play(m,
        runs: 1, wicket: WicketType.runOut, outId: 'A2');
    expect(st.runs, 1);
    expect(st.wickets, 1);
    expect(st.bowlers['B1']!.wickets, 0);
    expect(st.batters['A2']!.out, isTrue);
    expect(st.batters['A1']!.out, isFalse);
    expect(st.batters['A1']!.runs, 1);
    expect(st.needsNewBatter, isTrue);

    m.innings[0].deliveries.last.newBatterId = 'A3';
    st = computeInnings(m, 0);
    expect(st.strikerId, 'A3');
    expect(st.nonStrikerId, 'A1');
  });

  test('only a run out is possible on a no-ball', () {
    expect(WicketType.bowled.allowedOn(DeliveryKind.noBall), isFalse);
    expect(WicketType.runOut.allowedOn(DeliveryKind.noBall), isTrue);
    expect(WicketType.caught.allowedOn(DeliveryKind.wide), isFalse);
    expect(WicketType.stumped.allowedOn(DeliveryKind.wide), isTrue);
  });

  test('all out ends the innings', () {
    final m = newMatch(players: 3); // 3 players -> 2 wickets end the innings
    play(m, wicket: WicketType.bowled);
    m.innings[0].deliveries.last.newBatterId = 'A3';
    final st = play(m, wicket: WicketType.lbw);
    expect(st.wickets, 2);
    expect(st.complete, isTrue);
    expect(st.completeReason, 'All out');
    expect(st.needsNewBatter, isFalse);
    expect(canScore(st), isFalse);
  });

  test('innings ends when the overs are used up', () {
    final m = newMatch(overs: 1);
    var st = play(m);
    for (var i = 0; i < 5; i++) {
      st = play(m);
    }
    expect(st.complete, isTrue);
    expect(st.completeReason, 'Overs completed');
  });

  // Helper: Team A scores 6 in a 1-over innings.
  CricketMatch firstInningsSix() {
    final m = newMatch(overs: 1);
    play(m, runs: 6);
    for (var i = 0; i < 5; i++) {
      play(m);
    }
    m.innings.add(Innings(
      battingIndex: 1,
      openStrikerId: 'B1',
      openNonStrikerId: 'B2',
      nextBowlerId: 'A1',
    ));
    return m;
  }

  test('successful chase: target shown, innings ends, result by wickets', () {
    final m = firstInningsSix();
    var st = play(m, inningsIndex: 1, runs: 6);
    expect(st.target, 7);
    expect(st.runsNeeded, 1);
    expect(st.complete, isFalse);
    st = play(m, inningsIndex: 1, runs: 1);
    expect(st.complete, isTrue);
    expect(st.completeReason, 'Target reached');
    expect(matchResult(m)!.text, 'Team B won by 3 wickets');
  });

  test('defending team wins by runs', () {
    final m = firstInningsSix();
    play(m, inningsIndex: 1, runs: 3);
    play(m, inningsIndex: 1, runs: 2);
    for (var i = 0; i < 4; i++) {
      play(m, inningsIndex: 1);
    }
    expect(matchResult(m)!.text, 'Team A won by 1 run');
  });

  test('tie', () {
    final m = firstInningsSix();
    play(m, inningsIndex: 1, runs: 6);
    for (var i = 0; i < 5; i++) {
      play(m, inningsIndex: 1);
    }
    m.tieAccepted = true; // keep the tie (no Super Over)
    expect(matchResult(m)!.text, 'Match tied');
  });

  test('undo = remove last delivery and replay', () {
    final m = newMatch();
    play(m, runs: 4);
    final before = play(m, runs: 1);
    expect(before.runs, 5);
    m.innings[0].deliveries.removeLast();
    final after = computeInnings(m, 0);
    expect(after.runs, 4);
    expect(after.strikerId, 'A1');
  });

  test('match survives a JSON round trip (saved locally and reopened)', () {
    final m = newMatch();
    play(m, runs: 2);
    play(m, kind: DeliveryKind.wide, runs: 1);
    play(m, wicket: WicketType.caught);
    m.innings[0].deliveries.last.newBatterId = 'A3';
    play(m, runs: 6);

    final copy = CricketMatch.fromJson(
      jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
    );
    final a = computeInnings(m, 0);
    final b = computeInnings(copy, 0);
    expect(b.runs, a.runs);
    expect(b.wickets, a.wickets);
    expect(b.legalBalls, a.legalBalls);
    expect(b.strikerId, a.strikerId);
    expect(copy.sides[0].players.length, 4);
  });

  test('extras are counted separately and added to the total', () {
    final m = newMatch();
    play(m, runs: 4); // 4 off the bat
    play(m, kind: DeliveryKind.wide, runs: 1); // wide + 1 run = 2 wides
    play(m, kind: DeliveryKind.noBall, runs: 6); // no-ball + 6 off the bat
    play(m, kind: DeliveryKind.bye, runs: 2); // 2 byes
    final st = play(m, kind: DeliveryKind.legBye, runs: 1); // 1 leg-bye
    expect(st.batRuns, 10);
    expect(st.wides, 2);
    expect(st.noBalls, 1);
    expect(st.byes, 2);
    expect(st.legByes, 1);
    expect(st.extrasTotal, 6);
    expect(st.runs, st.batRuns + st.extrasTotal); // total = bat + extras
    expect(st.runs, 16);
    // byes and leg-byes are not charged to the bowler
    expect(st.bowlers['B1']!.runs, 4 + 2 + 1 + 6);
  });

  test('free hit after a no-ball: only a run out, and it carries over wides', () {
    final m = newMatch();
    var st = play(m);
    expect(st.freeHit, isFalse);
    st = play(m, kind: DeliveryKind.noBall);
    expect(st.freeHit, isTrue);
    st = play(m, kind: DeliveryKind.wide); // wide on the free hit
    expect(st.freeHit, isTrue);
    st = play(m, runs: 1); // legal ball ends the free hit
    expect(st.freeHit, isFalse);
  });

  test('maximum overs per bowler follows the ICC one-fifth rule', () {
    expect(calcMaxOversPerBowler(20, 11), 4); // T20
    expect(calcMaxOversPerBowler(50, 11), 10); // 50-over match
    expect(calcMaxOversPerBowler(10, 11), 2); // T10
    expect(calcMaxOversPerBowler(7, 11), 2); // rounded up
    expect(calcMaxOversPerBowler(20, 3), 7); // tiny team: innings can finish
    expect(computeInnings(newMatch(overs: 20, players: 11), 0).maxOversPerBowler, 4);
  });

  test('progress chart points follow the runs over by over', () {
    final m = newMatch(overs: 2);
    for (var i = 0; i < 6; i++) {
      play(m, runs: 1);
    }
    m.innings[0].nextBowlerId = 'B2';
    play(m, wicket: WicketType.bowled);
    final pts = inningsProgress(m, 0);
    expect(pts.first.runs, 0);
    expect(pts[1].overs, 1.0);
    expect(pts[1].runs, 6);
    expect(pts.last.wicket, isTrue);
    expect(pts.last.runs, 6);
  });

  test('over summaries give runs, wickets and extras for each over', () {
    final m = newMatch(overs: 2);
    play(m, runs: 4);
    play(m, kind: DeliveryKind.wide); // an extra, not one of the six balls
    for (var i = 0; i < 4; i++) {
      play(m);
    }
    play(m, wicket: WicketType.bowled); // the 6th legal ball
    final overs = inningsOvers(m, 0);
    expect(overs.length, 1);
    expect(overs[0].balls, 6);
    expect(overs[0].runs, 5); // 4 off the bat + 1 wide
    expect(overs[0].extras, 1);
    expect(overs[0].wickets, 1);
    expect(overs[0].totalRuns, 5);
    expect(overs[0].wides, 1);
  });

  test('the last over and the current over are kept apart', () {
    final m = newMatch(overs: 2);
    for (var i = 0; i < 6; i++) {
      play(m);
    }
    m.innings[0].nextBowlerId = 'B2';
    play(m, runs: 1);
    final st = play(m, kind: DeliveryKind.wide);
    expect(st.previousOver.length, 6);
    expect(st.currentOver.length, 2);
    expect(ordinal(1), '1st');
    expect(ordinal(2), '2nd');
    expect(ordinal(11), '11th');
    expect(ordinal(23), '23rd');
    expect(ordinal(35), '35th');
  });

  test('ball steps: one per legal ball, extras grouped with the next ball', () {
    final m = newMatch(overs: 2);
    play(m, runs: 1);
    play(m, kind: DeliveryKind.wide);
    play(m, runs: 4);
    final steps = inningsBalls(m, 0);
    expect(steps.length, 2);
    expect(steps[0].ball, 1);
    expect(steps[1].ball, 2);
    expect(steps[1].deliveries.length, 2); // the wide and the four
    expect(steps[1].totalRuns, 1 + 1 + 4);
    expect(steps[1].totalExtras, 1);
  });

  test('a tied match goes to a Super Over and the Super Over decides it', () {
    final m = firstInningsSix();
    play(m, inningsIndex: 1, runs: 6);
    for (var i = 0; i < 5; i++) {
      play(m, inningsIndex: 1);
    }
    expect(isMatchComplete(m), isFalse); // level: not finished yet
    expect(tieNeedsDecision(m), isTrue);

    // Super Over 1: Team B (batted second) bats first and scores 6
    m.innings.add(newSuperOverInnings(m));
    expect(m.innings[2].isSuperOver, isTrue);
    expect(m.innings[2].battingIndex, 1);
    m.innings[2]
      ..openStrikerId = 'B1'
      ..openNonStrikerId = 'B2'
      ..nextBowlerId = 'A1';
    expect(computeInnings(m, 2).maxWickets, 2); // two wickets in a Super Over
    play(m, inningsIndex: 2, runs: 6);
    for (var i = 0; i < 5; i++) {
      play(m, inningsIndex: 2);
    }
    expect(computeInnings(m, 2).complete, isTrue); // one over only
    expect(computeInnings(m, 2).runs, 6);

    // Team A chases 7 in the Super Over and gets there
    m.innings.add(newSuperOverInnings(m));
    expect(m.innings[3].battingIndex, 0);
    m.innings[3]
      ..openStrikerId = 'A1'
      ..openNonStrikerId = 'A2'
      ..nextBowlerId = 'B1';
    expect(computeInnings(m, 3).target, 7);
    play(m, inningsIndex: 3, runs: 6);
    play(m, inningsIndex: 3, runs: 1);
    expect(isMatchComplete(m), isTrue);
    final result = matchResult(m)!;
    expect(result.text, 'Team A won the Super Over');
    expect(result.winnerIndex, 0);
    expect(tieNeedsDecision(m), isFalse);

    // the Super Over survives saving
    final copy = CricketMatch.fromJson(
      jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
    );
    expect(copy.innings[3].isSuperOver, isTrue);
    expect(matchResult(copy)!.text, 'Team A won the Super Over');
  });
}
