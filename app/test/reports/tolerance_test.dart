import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateReading', () {
    const shaft = Tolerance(unit: 'мм', nominal: 170, min: 169.975, max: 170);

    test('inside with a margin is within', () {
      expect(evaluateReading(169.987, shaft), ToleranceStatus.within);
    });

    test('a bound itself is inside but near the limit', () {
      expect(evaluateReading(169.975, shaft), ToleranceStatus.nearLimit);
      expect(evaluateReading(170, shaft), ToleranceStatus.nearLimit);
      expect(evaluateReading(169.998, shaft), ToleranceStatus.nearLimit);
    });

    test('beyond a bound is outside', () {
      expect(evaluateReading(169.974, shaft), ToleranceStatus.outside);
      expect(evaluateReading(170.001, shaft), ToleranceStatus.outside);
    });

    test('negative clearance (interference fit) works', () {
      const fit = Tolerance(unit: 'мм', min: -0.033, max: 0.017);
      expect(evaluateReading(-0.01, fit), ToleranceStatus.within);
      expect(evaluateReading(-0.04, fit), ToleranceStatus.outside);
    });

    test('one-sided lower bound, spring load', () {
      const load = Tolerance(unit: 'Н', min: 173.4);
      expect(evaluateReading(200, load), ToleranceStatus.within);
      expect(evaluateReading(175, load), ToleranceStatus.nearLimit);
      expect(evaluateReading(170, load), ToleranceStatus.outside);
    });

    test('repair limit below nominal acts as lower bound', () {
      const washer = Tolerance(unit: 'мм', nominal: 3, limit: 2.5);
      expect(washer.lowerBound, 2.5);
      expect(evaluateReading(2.4, washer), ToleranceStatus.outside);
      expect(evaluateReading(2.9, washer), ToleranceStatus.within);
    });

    test('no bounds means no tolerance', () {
      const bare = Tolerance(unit: 'мм', nominal: 12);
      expect(evaluateReading(12, bare), ToleranceStatus.noTolerance);
    });
  });

  group('parsing and formatting', () {
    test('comma, dot, spaces and minus sign are accepted', () {
      expect(parseDecimal('169,975'), 169.975);
      expect(parseDecimal(' 0.5 '), 0.5);
      expect(parseDecimal('−0,02'), -0.02);
      expect(parseDecimal('1 234,5'), 1234.5);
      expect(parseDecimal('12,3,4'), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal(''), isNull);
    });

    test('canonical text keeps the typed digits', () {
      expect(canonicalDecimal('170,000'), '170.000');
      expect(canonicalDecimal('+0,5'), '0.5');
      expect(canonicalDecimal('x'), isNull);
    });

    test('tolerance is described in Russian style', () {
      const shaft = Tolerance(unit: 'мм', nominal: 170, min: 169.975, max: 170);
      expect(describeTolerance(shaft), '169,975…170,000 мм · ном. 170,000');
      const load = Tolerance(unit: 'Н', min: 173.4);
      expect(describeTolerance(load), '≥ 173,4 Н');
      expect(formatDecimal(2.5), '2,5');
      expect(formatDecimal(3), '3');
    });
  });
}
