import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Local persistence (SharedPreferences, stored as JSON on the phone) plus an
/// in-memory copy the UI listens to. No Internet is ever needed.
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this.teams, this.matches);

  final SharedPreferences _prefs;
  final List<Team> teams;
  final List<CricketMatch> matches;

  static const String _teamsKey = 'teams_v1';
  static const String _matchesKey = 'matches_v1';

  static Future<AppStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final teams = <Team>[];
    final matches = <CricketMatch>[];

    try {
      final raw = prefs.getString(_teamsKey);
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          try {
            teams.add(Team.fromJson(e as Map<String, dynamic>));
          } catch (err) {
            debugPrint('Skipping unreadable team: $err');
          }
        }
      }
      final rawMatches = prefs.getString(_matchesKey);
      if (rawMatches != null) {
        for (final e in jsonDecode(rawMatches) as List) {
          try {
            matches.add(CricketMatch.fromJson(e as Map<String, dynamic>));
          } catch (err) {
            debugPrint('Skipping unreadable match: $err');
          }
        }
      }
    } catch (err) {
      debugPrint('Could not read saved data: $err');
    }
    return AppStore._(prefs, teams, matches);
  }

  Future<void> _persistTeams() => _prefs.setString(
      _teamsKey, jsonEncode(teams.map((t) => t.toJson()).toList()));

  Future<void> _persistMatches() => _prefs.setString(
      _matchesKey, jsonEncode(matches.map((m) => m.toJson()).toList()));

  Future<void> upsertTeam(Team t) async {
    final i = teams.indexWhere((x) => x.id == t.id);
    if (i < 0) {
      teams.add(t);
    } else {
      teams[i] = t;
    }

    // Keep saved matches in step with renamed players / renamed team, so a
    // corrected name shows everywhere (scorecards and player statistics).
    // Players who were removed from the team keep their old name in old matches.
    var matchesChanged = false;
    for (final m in matches) {
      for (final side in m.sides) {
        if (side.teamId != t.id) continue;
        if (side.name != t.name) {
          side.name = t.name;
          matchesChanged = true;
        }
        for (var k = 0; k < side.players.length; k++) {
          final old = side.players[k];
          for (final p in t.players) {
            if (p.id == old.id && p.name != old.name) {
              side.players[k] = p;
              matchesChanged = true;
            }
          }
        }
      }
    }

    notifyListeners();
    await _persistTeams();
    if (matchesChanged) await _persistMatches();
  }

  Future<void> deleteTeam(String id) async {
    teams.removeWhere((t) => t.id == id);
    notifyListeners();
    await _persistTeams();
  }

  /// Saves (or updates) a match. Called after every delivery, so a match is
  /// never lost if the app is closed in the middle of an over.
  Future<void> upsertMatch(CricketMatch m) async {
    final i = matches.indexWhere((x) => x.id == m.id);
    if (i < 0) {
      matches.insert(0, m);
    } else {
      matches[i] = m;
    }
    notifyListeners();
    await _persistMatches();
  }

  Future<void> deleteMatch(String id) async {
    matches.removeWhere((m) => m.id == id);
    notifyListeners();
    await _persistMatches();
  }
}
