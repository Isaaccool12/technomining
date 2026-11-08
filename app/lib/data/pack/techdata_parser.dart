/// Unit described by a pack: a machine book lists several, a unit pack one.
final class ParsedUnit {
  /// Creates a unit.
  const ParsedUnit({
    required this.code,
    required this.name,
    required this.unitType,
  });

  /// Unit code used by the `aggs` labels (`eng`, `trans`).
  final String code;

  /// Display name.
  final String name;

  /// Unit type (`ДВС`, `КПП`), empty when the pack does not say.
  final String unitType;
}

/// Tolerance or torque read from `techdata.json`.
final class ParsedSpec {
  /// Creates an entry.
  const ParsedSpec({
    required this.key,
    required this.isTorque,
    required this.name,
    required this.unit,
    required this.nominal,
    required this.min,
    required this.max,
    required this.limit,
    required this.specKind,
    required this.note,
    required this.torqueText,
    required this.procKey,
    required this.procTitle,
    required this.procCode,
    required this.page,
    required this.unitCodes,
  });

  /// Key unique inside the pack.
  final String key;

  /// Whether this is a tightening torque rather than a tolerance.
  final bool isTorque;

  /// Parameter name.
  final String name;

  /// Unit of measure (`мм`, `Н`, `Н·м`).
  final String unit;

  /// Nominal (standard) size.
  final double? nominal;

  /// Lower bound of the tolerance.
  final double? min;

  /// Upper bound of the tolerance.
  final double? max;

  /// Repair limit.
  final double? limit;

  /// Kind label from the converter (`зазор`, `нагрузка`), may be empty.
  final String specKind;

  /// Free note from the source table.
  final String note;

  /// Torque as printed in the manual (`14,7–34 Н·м`).
  final String torqueText;

  /// Key of the procedure holding the value.
  final String procKey;

  /// Title of that procedure.
  final String procTitle;

  /// Factory page code of that procedure.
  final String procCode;

  /// Source page.
  final int? page;

  /// Units the value belongs to.
  final List<String> unitCodes;
}

/// Units of a pack from its `manual` block. A book lists them in `aggs`;
/// a unit pack is one unit coded by `agg`.
List<ParsedUnit> parsePackUnits(Map<String, dynamic> manual) {
  final aggs = manual['aggs'];
  if (aggs is List<dynamic>) {
    final units = <ParsedUnit>[
      for (final entry in aggs.whereType<Map<String, dynamic>>())
        if (_text(entry, 'code').isNotEmpty)
          ParsedUnit(
            code: _text(entry, 'code'),
            name: _text(entry, 'name'),
            unitType: _text(entry, 'type'),
          ),
    ];
    if (units.isNotEmpty) return units;
  }
  final code = _text(manual, 'agg');
  return [
    ParsedUnit(
      code: code.isEmpty ? 'unit' : code,
      name: _text(manual, 'title'),
      unitType: _text(manual, 'unitType'),
    ),
  ];
}

/// Tolerances and torques of `techdata.json`. Entries without `aggs` belong
/// to [defaultUnit]. Never throws on malformed values.
List<ParsedSpec> parseTechdata(
  Map<String, dynamic> techdata,
  String defaultUnit,
) {
  final result = <ParsedSpec>[];
  final specs = techdata['specs'];
  if (specs is List<dynamic>) {
    for (final entry in specs.whereType<Map<String, dynamic>>()) {
      final name = _text(entry, 'name');
      if (name.isEmpty) continue;
      result.add(
        _spec(
          entry,
          key: 's${result.length}',
          isTorque: false,
          name: name,
          unit: _text(entry, 'unit'),
          torqueText: '',
          defaultUnit: defaultUnit,
        ),
      );
    }
  }
  final torques = techdata['torques'];
  if (torques is List<dynamic>) {
    for (final entry in torques.whereType<Map<String, dynamic>>()) {
      final nm = _text(entry, 'nm');
      if (nm.isEmpty) continue;
      final operation = _text(entry, 'op');
      final kgm = _text(entry, 'kgm');
      result.add(
        _spec(
          entry,
          key: 't${result.length}',
          isTorque: true,
          name: operation.isEmpty ? _text(entry, 'title') : operation,
          unit: 'Н·м',
          torqueText: kgm.isEmpty ? '$nm Н·м' : '$nm Н·м {$kgm}',
          defaultUnit: defaultUnit,
        ),
      );
    }
  }
  return result;
}

ParsedSpec _spec(
  Map<String, dynamic> entry, {
  required String key,
  required bool isTorque,
  required String name,
  required String unit,
  required String torqueText,
  required String defaultUnit,
}) {
  final aggs = entry['aggs'];
  final codes = aggs is List<dynamic>
      ? aggs.whereType<String>().toList()
      : <String>[];
  final page = entry['page'];
  return ParsedSpec(
    key: key,
    isTorque: isTorque,
    name: name,
    unit: unit,
    nominal: _number(entry['nom']),
    min: _number(entry['min']),
    max: _number(entry['max']),
    limit: _number(entry['limit']),
    specKind: _text(entry, 'kind'),
    note: _text(entry, 'note'),
    torqueText: torqueText,
    procKey: _text(entry, 'proc'),
    procTitle: _text(entry, 'title'),
    procCode: _text(entry, 'code'),
    page: page is int ? page : null,
    unitCodes: codes.isEmpty ? [defaultUnit] : codes,
  );
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

String _text(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value : '';
}
