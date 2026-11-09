import 'package:flutter_test/flutter_test.dart';

import '../lib/team_logo.dart';

void main() {
  test('names that look like random typing get the general logo', () {
    expect(looksRandomName('ajfhfj'), isTrue);
    expect(looksRandomName('Dhdh'), isTrue);
    expect(looksRandomName('btw'), isTrue);
    expect(looksRandomName('qwrtp'), isTrue);
  });

  test('real team names get initials', () {
    expect(looksRandomName('Pakistan Kings'), isFalse);
    expect(looksRandomName('Indian Legends'), isFalse);
    expect(looksRandomName('KKR'), isFalse);
    expect(teamInitials('Pakistan Kings'), 'PK');
    expect(teamInitials('Indian Legends'), 'IL');
    expect(teamInitials('Warriors'), 'WA');
  });
}
