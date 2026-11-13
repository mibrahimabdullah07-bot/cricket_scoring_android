import 'package:flutter/material.dart';

import '../engine.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'career_stats_page.dart';
import 'match_setup_page.dart';
import 'scorecard_page.dart';
import 'scoring_page.dart';
import 'team_editor_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  void _newMatch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MatchSetupPage(store: widget.store)),
    );
  }

  void _newTeam() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TeamEditorPage(store: widget.store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Cricket Scorer' : 'My teams'),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Player statistics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CareerStatsPage(store: widget.store),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _MatchesTab(store: widget.store),
          _TeamsTab(store: widget.store),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tab == 0 ? _newMatch : _newTeam,
        icon: Icon(_tab == 0 ? Icons.sports_cricket : Icons.group_add),
        label: Text(_tab == 0 ? 'New match' : 'New team'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.sports_cricket), label: 'Matches'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Teams'),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final matches = store.matches;
        if (matches.isEmpty) {
          return const _EmptyState(
            icon: Icons.sports_cricket,
            message:
                'No matches yet.\nCreate two teams, then tap "New match".',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: matches.length,
          itemBuilder: (context, i) =>
              _MatchCard(store: store, match: matches[i]),
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.store, required this.match});

  final AppStore store;
  final CricketMatch match;

  void _open(BuildContext context, {bool scorecardOnly = false}) {
    final finished = isMatchComplete(match);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => (finished || scorecardOnly)
            ? ScorecardPage(match: match)
            : ScoringPage(store: store, match: match),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Delete match?',
      message: '${match.sides[0].name} vs ${match.sides[1].name} will be removed from this phone.',
      yes: 'Delete',
    );
    if (ok) await store.deleteMatch(match.id);
  }

  @override
  Widget build(BuildContext context) {
    final finished = isMatchComplete(match);
    final result = matchResult(match);
    final scores = <String>[];
    for (var i = 0; i < match.innings.length; i++) {
      final st = computeInnings(match, i);
      scores.add(st.needsOpeners
          ? '${st.battingTeamName}${i >= 2 ? ' (Super Over)' : ''}: waiting to start'
          : '${st.battingTeamName}${i >= 2 ? ' (Super Over)' : ''} ${st.runs}/${st.wickets} (${oversText(st.legalBalls)})');
    }
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${match.sides[0].name} vs ${match.sides[1].name}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDate(match.date)} - ${match.venue} - ${match.oversLimit} overs',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(scores.join('\n')),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          finished ? Icons.check_circle : Icons.play_circle,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            finished ? (result?.text ?? 'Completed') : 'In progress - tap to continue',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'scorecard') {
                    _open(context, scorecardOnly: true);
                  } else if (v == 'delete') {
                    _delete(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'scorecard', child: Text('Scorecard')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teams
// ---------------------------------------------------------------------------

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final teams = store.teams;
        if (teams.isEmpty) {
          return const _EmptyState(
            icon: Icons.groups,
            message: 'No teams yet.\nTap "New team" and add your players.\nTeams are saved on this phone for later matches.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: teams.length,
          itemBuilder: (context, i) {
            final t = teams[i];
            final short = t.players.length < kMinPlayersPerTeam;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(t.name),
                subtitle: Text(
                  '${t.players.length} players'
                  '${short ? ' - needs at least $kMinPlayersPerTeam to play' : ''}',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeamEditorPage(store: store, team: t),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete team',
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'Delete team?',
                      message:
                          '${t.name} will be removed. Past matches keep their scorecards.',
                      yes: 'Delete',
                    );
                    if (ok) await store.deleteTeam(t.id);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
