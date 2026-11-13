import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'scoring_page.dart';

/// Step-by-step "new match" wizard:
///   1 Teams  ->  2 Venue & date  ->  3 Overs  ->  4 Toss (coin flip) & decision
class MatchSetupPage extends StatefulWidget {
  const MatchSetupPage({super.key, required this.store});

  final AppStore store;

  @override
  State<MatchSetupPage> createState() => _MatchSetupPageState();
}

class _MatchSetupPageState extends State<MatchSetupPage>
    with TickerProviderStateMixin {
  static const List<String> _titles = [
    'Teams',
    'Venue & date',
    'Overs',
    'Toss',
  ];

  final PageController _page = PageController();
  late final AnimationController _coin;
  int _step = 0;

  Team? _teamA;
  Team? _teamB;
  final Set<String> _xiA = <String>{};
  final Set<String> _xiB = <String>{};

  final TextEditingController _venue = TextEditingController();
  final TextEditingController _overs = TextEditingController();
  DateTime _date = DateTime.now();

  int _headsTeam = 0; // which team calls Heads (the other gets Tails)
  int? _tossWinner; // 0 = Team A, 1 = Team B
  bool? _electBat; // true = bat, false = bowl
  bool _flipping = false;
  double _coinEnd = 0;

  /// Which side bats first, worked out from the toss and the decision.
  int get _battingFirst => (_tossWinner == 0) == (_electBat == true) ? 0 : 1;

  @override
  void initState() {
    super.initState();
    _coin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void dispose() {
    _coin.dispose();
    _page.dispose();
    _venue.dispose();
    _overs.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showError(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.error_outline, color: Theme.of(ctx).colorScheme.error),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  int? get _oversValue {
    final v = int.tryParse(_overs.text.trim());
    if (v == null || v < 1 || v > kMaxOvers) return null;
    return v;
  }

  /// Reasons the team step is not finished yet (empty = ready).
  List<String> get _teamProblems {
    final p = <String>[];
    final a = _teamA;
    final b = _teamB;
    if (a == null || b == null) {
      p.add('You must select both teams in order to play a match.');
      return p;
    }
    if (_xiA.length < kMinPlayersPerTeam) {
      p.add('${a.name} needs at least $kMinPlayersPerTeam players selected '
          'in order to play a match (it has ${_xiA.length}).');
    }
    if (_xiB.length < kMinPlayersPerTeam) {
      p.add('${b.name} needs at least $kMinPlayersPerTeam players selected '
          'in order to play a match (it has ${_xiB.length}).');
    }
    if (_xiA.length != _xiB.length) {
      p.add('Both teams must have the same number of players in order to '
          'play a match. ${a.name} has ${_xiA.length} and ${b.name} has '
          '${_xiB.length}. Tick or untick players so the numbers match.');
    }
    return p;
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _page.animateToPage(
      step,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  void _back() {
    if (_flipping || _step == 0) return;
    _goTo(_step - 1);
  }

  Future<void> _next() async {
    if (_step == 0) {
      final problems = _teamProblems;
      if (problems.isNotEmpty) {
        await _showError(
          (_teamA == null || _teamB == null)
              ? 'Teams required'
              : 'Teams are not ready',
          problems.join('\n\n'),
        );
        return;
      }
      _goTo(1);
    } else if (_step == 1) {
      if (_venue.text.trim().isEmpty) {
        await _showError('Venue required',
            'You must select the venue in order to play a match.');
        return;
      }
      _goTo(2);
    } else if (_step == 2) {
      if (_oversValue == null) {
        await _showError('Overs required',
            'You must select the number of overs in order to play a match. '
            'Choose T10, T20 or ODI, or enter a number between 1 and $kMaxOvers.');
        return;
      }
      _goTo(3);
    } else {
      await _start();
    }
  }

  Future<void> _pickTeam(bool isA) async {
    final other = isA ? _teamB : _teamA;
    final options =
        widget.store.teams.where((t) => t.id != other?.id).toList();
    final t = await pickOne<Team>(
      context,
      title: isA ? 'Select Team A' : 'Select Team B',
      items: options,
      label: (t) => '${t.name} (${t.players.length} players)',
    );
    if (t == null) return;
    setState(() {
      final xi = isA ? _xiA : _xiB;
      xi
        ..clear()
        ..addAll(t.players.take(kMaxPlayersPerTeam).map((p) => p.id));
      if (isA) {
        _teamA = t;
      } else {
        _teamB = t;
      }
      // a new team means a new toss
      _tossWinner = null;
      _electBat = null;
      _coin.reset();
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  void _flipCoin() {
    if (_flipping || _tossWinner != null) return;
    final heads = math.Random().nextBool();
    final winner = heads ? _headsTeam : 1 - _headsTeam;
    _coinEnd = 6 * 2 * math.pi + (heads ? 0 : math.pi);
    setState(() => _flipping = true);
    HapticFeedback.mediumImpact();
    _coin.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _flipping = false;
        _tossWinner = winner;
      });
      HapticFeedback.heavyImpact();
    });
  }

  MatchSide _side(Team t, Set<String> xi) => MatchSide(
        teamId: t.id,
        name: t.name,
        players: t.players.where((p) => xi.contains(p.id)).toList(),
      );

  Future<void> _start() async {
    final a = _teamA;
    final b = _teamB;
    final overs = _oversValue;
    if (a == null ||
        b == null ||
        overs == null ||
        _tossWinner == null ||
        _electBat == null ||
        _teamProblems.isNotEmpty) {
      return;
    }
    final match = CricketMatch(
      id: newId(),
      venue: _venue.text.trim(),
      date: _date,
      createdAt: DateTime.now(),
      oversLimit: overs,
      sides: [_side(a, _xiA), _side(b, _xiB)],
      innings: [Innings(battingIndex: _battingFirst)],
    );
    await widget.store.upsertMatch(match);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ScoringPage(store: widget.store, match: match),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Step 1: teams
  // ------------------------------------------------------------------

  Widget _teamTile(String label, Team? team, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: Text(team?.name ?? 'Select $label'),
        subtitle: Text(team == null
            ? label
            : '$label - ${team.players.length} saved players'),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: onTap,
      ),
    );
  }

  Widget _xiTile(Team team, Set<String> xi) {
    return Card(
      child: ExpansionTile(
        title: Text(
            '${team.name}: playing ${xi.length} (max $kMaxPlayersPerTeam)'),
        children: [
          for (final p in team.players)
            CheckboxListTile(
              dense: true,
              title: Text(p.name),
              value: xi.contains(p.id),
              onChanged: (v) {
                if (v == true) {
                  if (xi.length >= kMaxPlayersPerTeam) {
                    _snack('A team can have at most $kMaxPlayersPerTeam players.');
                    return;
                  }
                  setState(() => xi.add(p.id));
                } else {
                  setState(() => xi.remove(p.id));
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _teamsPage() {
    final cs = Theme.of(context).colorScheme;
    final ready = _teamProblems.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _teamTile('Team A', _teamA, () => _pickTeam(true)),
        _teamTile('Team B', _teamB, () => _pickTeam(false)),
        if (_teamA != null) _xiTile(_teamA!, _xiA),
        if (_teamB != null) _xiTile(_teamB!, _xiB),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: ready
              ? Row(
                  key: const ValueKey('ready'),
                  children: [
                    Icon(Icons.check_circle, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Both teams are ready: ${_xiA.length} players each.',
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('not-ready')),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Step 2: venue and date
  // ------------------------------------------------------------------

  Widget _venuePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Where is the match being played?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _venue,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Venue / match name',
            prefixIcon: Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Date'),
            subtitle: Text(formatDate(_date)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _pickDate,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Step 3: overs
  // ------------------------------------------------------------------

  Widget _presetCard(String name, int overs) {
    final cs = Theme.of(context).colorScheme;
    final selected = _oversValue == overs;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _overs.text = '$overs'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text('$overs overs'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _oversPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'How many overs per innings?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _presetCard('T10', 10),
            const SizedBox(width: 10),
            _presetCard('T20', 20),
            const SizedBox(width: 10),
            _presetCard('ODI', 50),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _overs,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Or enter your own (1 to $kMaxOvers)',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Step 4: toss (coin flip) and decision
  // ------------------------------------------------------------------

  /// One side of the coin: just the word HEADS or TAILS, written in an
  /// embossed gold style inside a beaded rim.
  Widget _coinFace(int side) {
    final word = side == 0 ? 'HEADS' : 'TAILS';
    const dark = Color(0xFF6D4C00);
    Widget label(Color color, Offset shift) => Transform.translate(
          offset: shift,
          child: Text(
            word,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: color,
            ),
          ),
        );
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFFF3B0), Color(0xFFFFC928), Color(0xFFB8860B)],
        ),
        border: Border.all(color: const Color(0xFF8D6E08), width: 6),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size(138, 138), painter: _CoinRimPainter()),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 16, color: dark),
              const SizedBox(height: 4),
              SizedBox(
                width: 100,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Stack(
                    children: [
                      label(const Color(0xCCFFF3B0), const Offset(-1.2, -1.2)),
                      label(dark, Offset.zero),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Icon(Icons.star, size: 16, color: dark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coinWidget() {
    return SizedBox(
      height: 270,
      child: AnimatedBuilder(
        animation: _coin,
        builder: (context, _) {
          final v = _coin.value;
          final angle = _coinEnd * Curves.easeOutCubic.transform(v);
          final lift = math.sin(math.pi * v) * 110;
          final scale = 1 + math.sin(math.pi * v) * 0.25;
          final front = math.cos(angle) >= 0;
          final face = _coinFace(front ? 0 : 1);
          final shadowOpacity = (1 - lift / 160).clamp(0.2, 1.0).toDouble();
          return Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Opacity(
                  opacity: shadowOpacity * 0.5,
                  child: Container(
                    width: 120 - lift * 0.3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -lift),
                child: Transform.scale(
                  scale: scale,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateX(angle),
                    child: front
                        ? face
                        : Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationX(math.pi),
                            child: face,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _electCard(String label, Widget icon, bool value) {
    final cs = Theme.of(context).colorScheme;
    final selected = _electBat == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _electBat = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tossPage() {
    final cs = Theme.of(context).colorScheme;
    final aName = _teamA?.name ?? 'Team A';
    final bName = _teamB?.name ?? 'Team B';
    final headsName = _headsTeam == 0 ? aName : bName;
    final tailsName = _headsTeam == 0 ? bName : aName;
    final winner = _tossWinner;
    final winnerName = winner == 0 ? aName : bName;
    final battingName = _battingFirst == 0 ? aName : bName;

    Widget bottom;
    if (winner == null) {
      bottom = Column(
        key: const ValueKey('flip'),
        children: [
          Text('Who calls Heads?',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              ButtonSegment<int>(
                value: 0,
                label: Text(aName, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text(bName, overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {_headsTeam},
            onSelectionChanged: _flipping
                ? null
                : (s) => setState(() => _headsTeam = s.first),
          ),
          const SizedBox(height: 6),
          Text('$tailsName gets Tails',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _flipping ? null : _flipCoin,
            icon: const Icon(Icons.monetization_on_outlined),
            label: Text(_flipping ? 'Flipping...' : 'Flip the coin'),
          ),
        ],
      );
    } else {
      bottom = Column(
        key: const ValueKey('result'),
        children: [
          Text(
            '$winnerName won the toss!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text('$winnerName elected to...',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _electCard('Bat', const CricketBatIcon(size: 36), true),
              const SizedBox(width: 12),
              _electCard('Bowl', const CricketBallIcon(size: 32), false),
            ],
          ),
          if (_electBat != null) ...[
            const SizedBox(height: 14),
            Text('$battingName will bat first',
                style: Theme.of(context).textTheme.titleSmall),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Text('Time for the toss',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text('$headsName = Heads   |   $tailsName = Tails',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(height: 28),
        _coinWidget(),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: bottom,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Frame: step bar, pages, buttons
  // ------------------------------------------------------------------

  Widget _stepBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _titles.length; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    height: 6,
                    margin: EdgeInsets.only(right: i < _titles.length - 1 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              'Step ${_step + 1} of ${_titles.length}: ${_titles[_step]}',
              key: ValueKey(_step),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Cross-fades and gently scales each page while the pages slide.
  Widget _fx(int index, Widget child) {
    final active = _step == index;
    return AnimatedOpacity(
      opacity: active ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOut,
      child: AnimatedScale(
        scale: active ? 1.0 : 0.96,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
        child: child,
      ),
    );
  }

  Widget _bottomBar() {
    final last = _step == _titles.length - 1;
    final bool enabled;
    if (_flipping) {
      enabled = false;
    } else if (last) {
      enabled = _tossWinner != null && _electBat != null;
    } else {
      enabled = true;
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _flipping ? null : _back,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: enabled ? _next : null,
                child: Text(last ? 'Start match' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store.teams.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('New match')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You need at least two saved teams.\nGo to the Teams tab and create them first.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('New match')),
        body: Column(
          children: [
            _stepBar(),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _fx(0, _teamsPage()),
                  _fx(1, _venuePage()),
                  _fx(2, _oversPage()),
                  _fx(3, _tossPage()),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }
}

/// Beaded edge and an inner ring for the coin.
class _CoinRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final bead = Paint()..color = const Color(0xFF8D6E08);
    for (var i = 0; i < 44; i++) {
      final a = i * 2 * math.pi / 44;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.9),
        r * 0.02,
        bead,
      );
    }
    canvas.drawCircle(
      c,
      r * 0.8,
      Paint()
        ..color = const Color(0x886D4C00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CoinRimPainter old) => false;
}
