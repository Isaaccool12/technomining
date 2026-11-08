import 'package:engineer/features/reports/domain/tolerance.dart';

/// Automatic or manual verdict on a part.
enum PartGrade {
  /// Reuse.
  good('good', 'Годен'),

  /// Restore to a repair size.
  repair('repair', 'Ремонт'),

  /// Replace with a new part.
  replace('replace', 'Замена');

  const PartGrade(this.code, this.label);

  /// Stored code.
  final String code;

  /// Russian label.
  final String label;

  /// Parses a stored [code]; null when unknown.
  static PartGrade? tryCode(Object? code) {
    for (final grade in values) {
      if (grade.code == code) return grade;
    }
    return null;
  }
}

/// Verdict with the repair size it relies on.
typedef GradeResult = ({PartGrade grade, double? repairStep});

/// Standard repair steps of crankshaft journals: 0,25…1,00 US.
const List<double> standardRepairSteps = [0.25, 0.5, 0.75, 1];

const double _epsilon = 1e-9;

/// Grades [value]; null when there is no tolerance to compare with.
///
/// Outside the tolerance the part is repairable when some step of
/// [repairSteps] covers its deviation from the nominal.
GradeResult? gradeReading(
  double value,
  Tolerance tolerance,
  List<double> repairSteps,
) {
  final status = evaluateReading(value, tolerance);
  if (status == ToleranceStatus.noTolerance) return null;
  if (status != ToleranceStatus.outside) {
    return (grade: PartGrade.good, repairStep: null);
  }
  final base = tolerance.nominal ?? tolerance.lowerBound ?? tolerance.upperBound;
  if (base != null) {
    final deviation = (value - base).abs();
    final steps = [...repairSteps]..sort();
    for (final step in steps) {
      if (step + _epsilon >= deviation) {
        return (grade: PartGrade.repair, repairStep: step);
      }
    }
  }
  return (grade: PartGrade.replace, repairStep: null);
}

/// The worse of two verdicts; a replacement outweighs a repair.
GradeResult? worseGrade(GradeResult? a, GradeResult? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a.grade.index != b.grade.index) {
    return a.grade.index > b.grade.index ? a : b;
  }
  final stepA = a.repairStep ?? 0;
  final stepB = b.repairStep ?? 0;
  return stepA >= stepB ? a : b;
}

/// Label of a verdict: `Ремонт · 0,25 US`.
String gradeLabel(GradeResult result) {
  final step = result.repairStep;
  return step == null
      ? result.grade.label
      : '${result.grade.label} · ${formatDecimal(step)} US';
}

/// Shape of a "position × point × direction" measurement.
final class GridSpec {
  /// Creates a shape.
  const GridSpec({
    required this.rowLabel,
    required this.rowCount,
    required this.positions,
    required this.directions,
    this.repairSteps = const [],
  });

  /// Rebuilds a shape from stored JSON; null when malformed.
  static GridSpec? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final label = json['rowLabel'];
    final count = json['rows'];
    final positions = json['pos'];
    final directions = json['dir'];
    final steps = json['steps'];
    if (label is! String ||
        count is! int ||
        positions is! List<dynamic> ||
        directions is! List<dynamic>) {
      return null;
    }
    return GridSpec(
      rowLabel: label,
      rowCount: count,
      positions: positions.whereType<String>().toList(),
      directions: directions.whereType<String>().toList(),
      repairSteps: steps is List<dynamic>
          ? steps.whereType<num>().map((s) => s.toDouble()).toList()
          : const [],
    );
  }

  /// Word before the row number, for example `Цилиндр`.
  final String rowLabel;

  /// Number of rows, at least one.
  final int rowCount;

  /// Measuring planes, for example top / middle / bottom.
  final List<String> positions;

  /// Measuring directions, for example A / B.
  final List<String> directions;

  /// Available repair sizes; empty when the part cannot be restored.
  final List<double> repairSteps;

  /// JSON stored in the record.
  Map<String, Object?> toJson() => {
    'rowLabel': rowLabel,
    'rows': rowCount,
    'pos': positions,
    'dir': directions,
    if (repairSteps.isNotEmpty) 'steps': repairSteps,
  };
}

/// Key of one cell in the readings map.
String gridCellKey(int row, int position, int direction) =>
    '$row:$position:$direction';

/// Out-of-roundness of one plane: spread between its directions.
double? ovality(Iterable<double?> directionValues) {
  final values = directionValues.whereType<double>().toList();
  if (values.length < 2) return null;
  return _spread(values);
}

/// Taper along one direction: spread between its planes.
double? taper(Iterable<double?> positionValues) {
  final values = positionValues.whereType<double>().toList();
  if (values.length < 2) return null;
  return _spread(values);
}

double _spread(List<double> values) {
  var low = values.first;
  var high = values.first;
  for (final value in values) {
    if (value < low) low = value;
    if (value > high) high = value;
  }
  return high - low;
}

/// Maximum ovality and taper of one row of [values] (`[position][direction]`).
({double? ovality, double? taper}) rowDerived(
  List<List<double?>> values,
  int directionCount,
) {
  double? maxOvality;
  for (final plane in values) {
    final value = ovality(plane);
    if (value != null && (maxOvality == null || value > maxOvality)) {
      maxOvality = value;
    }
  }
  double? maxTaper;
  for (var d = 0; d < directionCount; d++) {
    final value = taper(values.map((plane) => plane[d]));
    if (value != null && (maxTaper == null || value > maxTaper)) {
      maxTaper = value;
    }
  }
  return (ovality: maxOvality, taper: maxTaper);
}

/// Grid presets offered when adding a measurement grid.
enum GridPreset {
  /// Cylinder liner bore.
  liner('Гильза: внутренний диаметр', 'Цилиндр', ['Верх', 'Середина', 'Низ'], [
    'A',
    'B',
  ], usesMains: false, repairable: false),

  /// Main journal.
  mainJournal('Коренная шейка', 'Шейка', ['Перед', 'Зад'], [
    'A',
    'B',
  ], usesMains: true, repairable: true),

  /// Connecting-rod journal.
  rodJournal('Шатунная шейка', 'Шейка', ['Перед', 'Зад'], [
    'A',
    'B',
  ], usesMains: false, repairable: true),

  /// Camshaft journal.
  camJournal('Шейка распределительного вала', 'Шейка', ['Перед', 'Зад'], [
    'Верт.',
    'Гориз.',
  ], usesMains: true, repairable: false),

  /// Anything else.
  custom('Своя сетка', 'Позиция', ['Точка'], [
    'A',
    'B',
  ], usesMains: false, repairable: false);

  const GridPreset(
    this.title,
    this.rowLabel,
    this.positions,
    this.directions, {
    required this.usesMains,
    required this.repairable,
  });

  /// Measurement name.
  final String title;

  /// Row word.
  final String rowLabel;

  /// Planes.
  final List<String> positions;

  /// Directions.
  final List<String> directions;

  /// Whether the row count follows the main journals, not the cylinders.
  final bool usesMains;

  /// Whether repair sizes apply.
  final bool repairable;

  /// Shape for a unit of the given composition.
  GridSpec spec(int cylinders, int mains) => GridSpec(
    rowLabel: rowLabel,
    rowCount: usesMains ? mains : cylinders,
    positions: positions,
    directions: directions,
    repairSteps: repairable ? standardRepairSteps : const [],
  );
}
