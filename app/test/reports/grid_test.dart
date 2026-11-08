import 'package:engineer/features/reports/domain/grid.dart';
import 'package:engineer/features/reports/domain/inspection.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const journal = Tolerance(unit: 'мм', nominal: 110, min: 109.98, max: 110);

  group('gradeReading', () {
    test('inside the tolerance is good', () {
      expect(
        gradeReading(109.99, journal, standardRepairSteps)?.grade,
        PartGrade.good,
      );
    });

    test('outside with a covering step is a repair to that step', () {
      final result = gradeReading(109.8, journal, standardRepairSteps);
      expect(result?.grade, PartGrade.repair);
      expect(result?.repairStep, 0.25);
      expect(gradeLabel(result!), 'Ремонт · 0,25 US');
    });

    test('beyond every step, or without steps, is a replacement', () {
      expect(
        gradeReading(108.5, journal, standardRepairSteps)?.grade,
        PartGrade.replace,
      );
      expect(gradeReading(109.8, journal, const [])?.grade, PartGrade.replace);
    });

    test('no tolerance gives no verdict', () {
      expect(gradeReading(1, const Tolerance(unit: 'мм'), const []), isNull);
    });
  });

  test('worseGrade prefers replacement, then the larger repair', () {
    const small = (grade: PartGrade.repair, repairStep: 0.25);
    const large = (grade: PartGrade.repair, repairStep: 0.5);
    const replace = (grade: PartGrade.replace, repairStep: null);
    expect(worseGrade(small, large), large);
    expect(worseGrade(large, replace), replace);
    expect(worseGrade(null, small), small);
  });

  group('derived values', () {
    test('ovality needs two directions', () {
      expect(ovality([1.0, null]), isNull);
      expect(ovality([10.0, 10.02]), closeTo(0.02, 1e-9));
    });

    test('row takes the maximum over planes and directions', () {
      final result = rowDerived([
        [10.0, 10.02],
        [10.05, 10.06],
        [null, null],
      ], 2);
      expect(result.ovality, closeTo(0.02, 1e-9));
      expect(result.taper, closeTo(0.05, 1e-9));
    });
  });

  test('GridSpec survives JSON', () {
    final spec = GridPreset.mainJournal.spec(6, 7);
    final copy = GridSpec.fromJson(<String, dynamic>{
      ...spec.toJson(),
    });
    expect(copy?.rowCount, 7);
    expect(copy?.repairSteps, standardRepairSteps);
    expect(GridSpec.fromJson('x'), isNull);
  });

  test('inspection list follows the unit type', () {
    expect(inspectionListFor('ДВС'), contains('Турбокомпрессор'));
    expect(inspectionListFor('АКПП'), contains('Клапаны управления'));
    expect(inspectionListFor('Мост'), contains('Дифференциал'));
    expect(inspectionListFor(''), contains('Корпус'));
  });

  test('an item counts as inspected only with some result', () {
    const empty = InspectionItem(id: 'a', name: 'x', isStandard: true);
    const clean = InspectionItem(
      id: 'a',
      name: 'x',
      isStandard: true,
      isClean: true,
    );
    expect(empty.isInspected, isFalse);
    expect(clean.isInspected, isTrue);
    expect(clean.summary, 'Без замечаний');
  });
}
