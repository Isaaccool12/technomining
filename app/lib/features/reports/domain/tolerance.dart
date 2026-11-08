import 'dart:math' as math;

/// Share of the tolerance band, next to an edge, that counts as "у предела".
const double nearLimitShare = 0.1;

/// Share of a one-sided bound that counts as "у предела".
const double nearOneSidedShare = 0.05;

const double _epsilon = 1e-9;

/// Result of checking a reading against its tolerance.
enum ToleranceStatus {
  /// Inside the tolerance with a margin: green, ✓.
  within,

  /// Inside the tolerance but close to an edge: yellow, !.
  nearLimit,

  /// Outside the tolerance: red, ✕.
  outside,

  /// The point has no tolerance to check against.
  noTolerance,
}

/// Tolerance of one measured parameter.
final class Tolerance {
  /// Creates a tolerance; any bound may be absent.
  const Tolerance({
    required this.unit,
    this.nominal,
    this.min,
    this.max,
    this.limit,
  });

  /// Unit of measure.
  final String unit;

  /// Nominal (standard) size.
  final double? nominal;

  /// Lower bound.
  final double? min;

  /// Upper bound.
  final double? max;

  /// Repair limit.
  final double? limit;

  /// Lower bound used for the check: [min], or [limit] below [nominal].
  double? get lowerBound {
    if (min != null) return min;
    final l = limit;
    final n = nominal;
    return l != null && n != null && l < n ? l : null;
  }

  /// Upper bound used for the check: [max], or [limit] above [nominal].
  double? get upperBound {
    if (max != null) return max;
    final l = limit;
    final n = nominal;
    return l != null && n != null && l > n ? l : null;
  }

  /// Whether there is anything to check a reading against.
  bool get isCheckable => lowerBound != null || upperBound != null;
}

/// Checks [value] against [tolerance]. A value on a bound is inside.
ToleranceStatus evaluateReading(double value, Tolerance tolerance) {
  final lo = tolerance.lowerBound;
  final hi = tolerance.upperBound;
  if (lo == null && hi == null) return ToleranceStatus.noTolerance;
  if ((lo != null && value < lo - _epsilon) ||
      (hi != null && value > hi + _epsilon)) {
    return ToleranceStatus.outside;
  }
  final margin = lo != null && hi != null
      ? (hi - lo) * nearLimitShare
      : math.max((lo ?? hi ?? 0).abs() * nearOneSidedShare, 1e-6);
  final nearLow = lo != null && value - lo < margin - _epsilon;
  final nearHigh = hi != null && hi - value < margin - _epsilon;
  return nearLow || nearHigh
      ? ToleranceStatus.nearLimit
      : ToleranceStatus.within;
}

final RegExp _decimalPattern = RegExp(r'^[-+]?(\d+(\.\d*)?|\.\d+)$');

/// Parses a reading typed with a comma or a dot; null when it is not a number.
double? parseDecimal(String text) {
  final cleaned = text
      .trim()
      .replaceAll(RegExp(r'[\s ]'), '')
      .replaceAll(',', '.')
      .replaceAll('−', '-');
  if (!_decimalPattern.hasMatch(cleaned)) return null;
  return double.tryParse(cleaned);
}

/// Canonical text of a typed reading: a dot as separator, no spaces.
String? canonicalDecimal(String text) {
  final value = parseDecimal(text);
  if (value == null) return null;
  return text
      .trim()
      .replaceAll(RegExp(r'[\s ]'), '')
      .replaceAll(',', '.')
      .replaceAll('−', '-')
      .replaceFirst('+', '');
}

int _decimalsOf(double value) {
  final text = value.toStringAsFixed(4);
  final trimmed = text.replaceFirst(RegExp(r'0+$'), '');
  final dot = trimmed.indexOf('.');
  return dot < 0 ? 0 : trimmed.length - dot - 1;
}

/// Formats [value] in Russian style with at least [decimals] digits.
String formatDecimal(double value, {int decimals = 0}) {
  final digits = math.max(decimals, _decimalsOf(value));
  return value.toStringAsFixed(digits).replaceAll('.', ',');
}

/// Human text of [tolerance]: `169,975…170,000 мм · ном. 170 · пред. 2,5`.
String describeTolerance(Tolerance tolerance) {
  final values = [
    tolerance.nominal,
    tolerance.min,
    tolerance.max,
    tolerance.limit,
  ].whereType<double>();
  final decimals = values.isEmpty ? 0 : values.map(_decimalsOf).reduce(math.max);
  String f(double v) => formatDecimal(v, decimals: decimals);
  final unit = tolerance.unit.isEmpty ? '' : ' ${tolerance.unit}';
  final min = tolerance.min;
  final max = tolerance.max;
  final parts = <String>[];
  if (min != null && max != null) {
    parts.add('${f(min)}…${f(max)}$unit');
  } else if (min != null) {
    parts.add('≥ ${f(min)}$unit');
  } else if (max != null) {
    parts.add('≤ ${f(max)}$unit');
  }
  final nominal = tolerance.nominal;
  if (nominal != null) parts.add('ном. ${f(nominal)}');
  final limit = tolerance.limit;
  if (limit != null) parts.add('пред. ${f(limit)}');
  return parts.join(' · ');
}
