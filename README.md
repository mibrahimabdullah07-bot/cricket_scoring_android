# Cricket Match Scoring App (EF101-P02)

Offline Android/Flutter app. The scorer enters only what happens on each ball;
the app applies the rules (legal balls, strike changes, innings end, target,
result).

## Run it
1. Copy `lib/`, `test/engine_test.dart`, `pubspec.yaml`, `analysis_options.yaml` into your Flutter project
   (keep your own project `name:` in pubspec if it differs; only make sure `shared_preferences` is a dependency).
2. Delete the default `test/widget_test.dart` (it refers to the old counter app).
3. `flutter pub get` -> `flutter analyze` -> `flutter test` -> `flutter run` (phone connected, USB debugging on).

## Architecture (what to explain in the viva)
```
UI (pages/*)  ->  engine.dart (pure Dart rules)  ->  models.dart (data)  ->  store.dart (SharedPreferences JSON on the phone)
```
* **Press a button -> output:** the page appends one `Delivery` to the innings,
  `computeInnings()` replays all deliveries to rebuild totals/overs/strike/figures,
  the screen redraws, and `AppStore.upsertMatch()` writes the whole match as JSON to local storage.
* **Runs on the phone only.** No server, API, database server or cloud. Internet is never used.
  Storage = `shared_preferences` (key-value file on the phone). Keys: `teams_v1`, `matches_v1`.
* **If storage were deleted:** teams and matches disappear; the app starts empty (no crash).
  A corrupted entry is skipped instead of crashing (`AppStore.open`).
* **Why delivery-level records?** Totals are never stored, only derived. So they cannot get out of sync,
  Undo = remove last delivery + replay, and a whole innings can be reconstructed.
* **Entities:** Team, Player, MatchSide (snapshot of a team for one match), CricketMatch, Innings,
  Delivery. BatterInnings / BowlerSpell are derived (`BatterLine`, `BowlerLine`).
* **Why Flutter/Dart + shared_preferences:** one codebase, runs offline, simple key-value JSON is enough
  for this data size.

## Requirement -> where it is
| Requirement | Where |
|---|---|
| Create/save team, add/retrieve players | `team_editor_page.dart`, `store.dart` |
| Block incomplete team (min `kMinPlayersPerTeam` = 3) | `models.dart` constant, `match_setup_page.dart` (`_problems`), team list hint |
| Match: two teams, date, venue, overs, batting team, playing XI | `match_setup_page.dart` |
| Select striker, non-striker, bowler before innings | `InningsSetupDialog` (`widgets.dart`), scoring is disabled until done (`canScore`) |
| Runs 0,1,2,3,4,6 | scoring pad |
| Wide, no-ball, bye, leg-bye (not legal balls for wide/no-ball) | `Delivery.isLegal`, `DeliveryKind` |
| Overs notation, auto strike change, new bowler each over | `computeInnings`, `oversText`, `needsBowler` |
| Batter: runs, balls, 1s 2s 3s 4s 6s; Bowler: overs, balls, runs, wickets | `BatterLine`, `BowlerLine`, scorecard |
| Wickets: bowled, caught, LBW, stumped, run out (+hit wicket) | `WicketDialog`, `WicketType` |
| Innings end by overs / wickets / chase | `computeInnings` (`complete`, `completeReason`) |
| Target and result | score header, `matchResult()` |
| Scorecard (total, wkts, overs, batters, bowlers, extras, FOW) | `scorecard_page.dart` |
| Save completed match and reopen summary | `AppStore.upsertMatch`, Matches tab |
| Works without Internet | nothing in the app uses the network |

## Scoring rules implemented 
| Event | Team runs | Legal ball | Batter | Bowler |
|---|---|---|---|---|
| Normal 0-6 | runs | yes | runs + ball faced | runs charged, ball counted |
| Wide (+n) | 1+n | **no** | no ball faced | 1+n charged, ball NOT counted |
| No-ball (+n off bat) | 1+n | **no** | n runs, ball faced | 1+n charged, ball NOT counted |
| No-ball + byes / leg-byes | 1+n | no | ball faced, no runs | only the 1 penalty charged |
| Bye / leg-bye (n) | n | yes | ball faced, no runs | **not** charged, ball counted |

Strike changes when the runs run are odd (incl. wides/byes), and at the end of every over.

| Dismissal | Bowler credit | Batter status | Notes |
|---|---|---|---|
| Bowled, Caught, LBW, Hit wicket | yes | out (striker) | new batter on strike |
| Stumped | yes | out (striker) | allowed on a wide |
| Run out | **no** | chosen batter (striker or non-striker) out | runs completed counted; scorer chooses who is on strike next |

Only a run out is allowed on a no-ball. Innings ends when: overs finished, all out (players - 1 wickets),
chase target reached, or the scorer ends it (menu). A bowler cannot bowl two consecutive overs.

## Required edge-case demo script
Create teams (>= 3 players each) -> New match -> T10 -> Start. Choose openers + bowler, then:
1. Dot, 1 (strike changes), 4 (boundary).
2. Mode **Wide** -> tap `Wd` (over does not advance).
3. Mode **No-ball** -> tap `Nb+4`.
4. **Wicket** -> Bowled -> choose next batter.
5. Finish the over -> app forces a new bowler (the previous bowler is not offered).
6. Finish/End innings -> "Start second innings" -> target is shown -> chase it -> result dialog.
7. Close the app completely, reopen: saved teams and the match are still there.

## Live-modification ideas (viva)
* Change minimum team size: `kMinPlayersPerTeam` in `models.dart`.
* Change preset overs: `match_setup_page.dart` (`T10/T20/ODI`).
* Change which dismissals credit the bowler: `WicketTypeX.creditsBowler`.
* Wrong data handling: empty names, duplicate players, overs outside 1-100, same team twice,
  too few players are all blocked with a visible message.

## Known limitations (state honestly)
* Single-innings-per-team limited-overs only; no Test rules (follow-on, declarations, 4 innings), no DLS.
* Penalty runs (5) and retired batters are not supported.
* "Caught" does not model batters crossing before the catch (the new batter simply takes strike).
* Data is in `shared_preferences`; it is not encrypted and is lost if the app data is cleared.
* Not compiled by the author of this README: run `flutter analyze` and `flutter test` first.
