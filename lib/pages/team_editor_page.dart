import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// Create a new team or edit a saved one (name + players).
class TeamEditorPage extends StatefulWidget {
  const TeamEditorPage({super.key, required this.store, this.team});

  final AppStore store;
  final Team? team;

  @override
  State<TeamEditorPage> createState() => _TeamEditorPageState();
}

class _TeamEditorPageState extends State<TeamEditorPage> {
  late final TextEditingController _name;
  final TextEditingController _newPlayers = TextEditingController();
  late final List<Player> _players;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.team?.name ?? '');
    _players = <Player>[...?widget.team?.players];
  }

  @override
  void dispose() {
    _name.dispose();
    _newPlayers.dispose();
    super.dispose();
  }

  /// Name of another saved team that already has a player with this name.
  String? _otherTeamWith(String name) {
    final lower = name.toLowerCase();
    for (final t in widget.store.teams) {
      if (t.id == widget.team?.id) continue;
      for (final p in t.players) {
        if (p.name.toLowerCase() == lower) return t.name;
      }
    }
    return null;
  }

  bool _hasPlayer(String name) =>
      _players.any((p) => p.name.toLowerCase() == name.toLowerCase());

  /// Accepts one name, or several separated by commas / new lines.
  void _addPlayers() {
    final names = _newPlayers.text
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (names.isEmpty) return;
    final problems = <String>[];
    setState(() {
      for (final n in names) {
        final other = _otherTeamWith(n);
        if (_players.length >= kMaxPlayersPerTeam) {
          problems.add('A team can have at most $kMaxPlayersPerTeam players. '
              '"$n" was not added.');
        } else if (_hasPlayer(n)) {
          problems.add('"$n" is already in this team.');
        } else if (other != null) {
          problems.add('"$n" already plays for $other. Player names must be '
              'different across teams (add a surname or initial).');
        } else {
          _players.add(Player(id: newId(), name: n));
        }
      }
      _newPlayers.clear();
      _error = problems.isEmpty ? null : problems.join('\n');
    });
  }

  Future<void> _rename(int index) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: _players[index].name),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final clash = _players.indexWhere(
        (p) => p.name.toLowerCase() == result.toLowerCase());
    if (clash >= 0 && clash != index) {
      setState(() => _error = 'A player called "$result" already exists.');
      return;
    }
    final unchanged = result.toLowerCase() == _players[index].name.toLowerCase();
    final other = unchanged ? null : _otherTeamWith(result);
    if (other != null) {
      setState(() => _error = '"$result" already plays for $other. Player '
          'names must be different across teams (add a surname or initial).');
      return;
    }
    setState(() {
      _players[index] = Player(id: _players[index].id, name: result);
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a team name.');
      return;
    }
    final clash = widget.store.teams.any((t) =>
        t.id != widget.team?.id && t.name.toLowerCase() == name.toLowerCase());
    if (clash) {
      setState(() => _error = 'A team called "$name" already exists.');
      return;
    }
    if (_players.length > kMaxPlayersPerTeam) {
      setState(() => _error = 'A team can have at most $kMaxPlayersPerTeam '
          'players. Remove ${_players.length - kMaxPlayersPerTeam} to save.');
      return;
    }
    final team = widget.team ?? Team(id: newId(), name: name);
    team.name = name;
    team.players
      ..clear()
      ..addAll(_players);
    await widget.store.upsertTeam(team);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enough = _players.length >= kMinPlayersPerTeam;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.team == null ? 'New team' : 'Edit team'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Team name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _newPlayers,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Add players',
                    helperText: 'One name, or several separated by commas / new lines',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addPlayers(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addPlayers,
                icon: const Icon(Icons.add),
                tooltip: 'Add',
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 16),
          Text(
            'Players (${_players.length}/$kMaxPlayersPerTeam)'
            '${enough ? '' : ' - at least $kMinPlayersPerTeam needed to play a match'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_players.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No players yet.'),
            ),
          for (var i = 0; i < _players.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(_players[i].name),
                onTap: () => _rename(i),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () => setState(() => _players.removeAt(i)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dialog owns its text controller, so the controller is only disposed
/// after the dialog has completely left the screen.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename player'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
