import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_scoring_app/models.dart';
import 'package:cricket_scoring_app/wagon_wheel.dart';

void main() {
  test('1, 2 and 3 runs stay inside the field', () {
    for (final runs in [1, 2, 3]) {
      expect(checkShot(runs, const Offset(0.4, 0.3)).error, isNull);
      expect(checkShot(runs, const Offset(0.75, 0.0)).error, isNotNull);
      expect(checkShot(runs, const Offset(0.9, 0.0)).error, isNotNull);
    }
  });

  test('a four must be on the rope ring and is snapped to the rope', () {
    expect(checkShot(4, const Offset(0.3, 0.2)).error, isNotNull); // middle
    expect(checkShot(4, const Offset(0.92, 0.0)).error, isNotNull); // six ring
    final c = checkShot(4, const Offset(0.75, 0.0));
    expect(c.error, isNull);
    expect(c.point.distance, closeTo(kBoundaryRadius, 0.001));
  });

  test('a six must be on the outer ring, beyond the rope', () {
    expect(checkShot(6, const Offset(0.2, 0.2)).error, isNotNull); // middle
    expect(checkShot(6, const Offset(0.75, 0.0)).error, isNotNull); // four ring
    final c = checkShot(6, const Offset(0.0, -0.95));
    expect(c.error, isNull);
    expect(c.point.distance, greaterThan(kBoundaryRadius));
  });

  test('the pitch itself is not a valid place', () {
    expect(checkShot(1, const Offset(0.01, 0.01)).error, isNotNull);
  });

  test('the shot direction is saved with the delivery', () {
    final d = Delivery(
      kind: DeliveryKind.normal,
      runs: 4,
      strikerId: 'A1',
      nonStrikerId: 'A2',
      bowlerId: 'B1',
    );
    d.shotX = 0.5;
    d.shotY = -0.6;
    final back = Delivery.fromJson(d.toJson());
    expect(back.shotX, 0.5);
    expect(back.shotY, -0.6);
  });
}
