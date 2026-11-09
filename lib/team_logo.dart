import 'package:flutter/material.dart';

/// True when a team name looks like random typing ("ajfhfj", "dhdh"): no
/// vowels, very few vowels, or a long run of consonants. Such teams get one
/// general logo instead of initials. Short all-capital names (KKR) count as
/// acronyms and are fine.
bool looksRandomName(String name) {
  final trimmed = name.trim();
  final lettersOnly = trimmed.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (lettersOnly.isEmpty) return true;
  if (lettersOnly.length >= 2 &&
      lettersOnly.length <= 4 &&
      lettersOnly == lettersOnly.toUpperCase()) {
    return false;
  }
  final letters = lettersOnly.toLowerCase();
  const vowels = 'aeiouy';
  var vowelCount = 0;
  var run = 0;
  var longestRun = 0;
  for (final ch in letters.split('')) {
    if (vowels.contains(ch)) {
      vowelCount++;
      run = 0;
    } else {
      run++;
      if (run > longestRun) longestRun = run;
    }
  }
  if (vowelCount == 0) return true;
  if (longestRun >= 5) return true;
  if (letters.length >= 5 && vowelCount / letters.length < 0.2) return true;
  return false;
}

/// "Pakistan Kings" -> "PK", "Warriors" -> "WA".
String teamInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length >= 2) {
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
  final w = words[0];
  return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
}

const List<List<Color>> _gradients = [
  [Color(0xFF2E7D32), Color(0xFF1B5E20)], // green
  [Color(0xFF1E88E5), Color(0xFF0D47A1)], // blue
  [Color(0xFFE53935), Color(0xFF8E1B1B)], // red
  [Color(0xFF8E24AA), Color(0xFF4A148C)], // purple
  [Color(0xFF00897B), Color(0xFF004D40)], // teal
  [Color(0xFFFB8C00), Color(0xFFE65100)], // orange
  [Color(0xFF3949AB), Color(0xFF1A237E)], // indigo
  [Color(0xFFD81B60), Color(0xFF880E4F)], // pink
];

/// Same name -> same number, on every phone and every run.
int _stableHash(String s) {
  var h = 7;
  for (final unit in s.trim().toLowerCase().codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return h;
}

/// A badge made from the team name: its initials on a colour picked from the
/// name. A name that looks like random typing gets one general cricket logo.
class TeamLogo extends StatelessWidget {
  const TeamLogo({super.key, required this.name, this.size = 64});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final general = looksRandomName(name);
    final colors = general
        ? const [Color(0xFF607D8B), Color(0xFF263238)]
        : _gradients[_stableHash(name) % _gradients.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0xCCFFFFFF), width: size * 0.04),
        boxShadow: [
          BoxShadow(
            color: const Color(0x55000000),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: general
          ? Icon(Icons.sports_cricket, color: Colors.white, size: size * 0.52)
          : Padding(
              padding: EdgeInsets.all(size * 0.12),
              child: FittedBox(
                child: Text(
                  teamInitials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
    );
  }
}
