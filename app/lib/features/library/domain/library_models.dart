/// Stable reasons why a pack could not be imported.
enum ImportFailure {
  /// The file is not a readable ZIP archive.
  notZip,

  /// Required parts of the pack are missing or malformed.
  badFormat,

  /// The pack format version is newer than the app supports.
  unsupportedVersion,

  /// Writing to the device storage failed.
  storage,
}

/// Stable reasons why a procedure cannot be shown.
enum ProcedureViewFailure {
  /// The procedure body is not present on the device.
  missing,
}

/// A manual (one unit of a machine) in the library.
final class ManualSummary {
  /// Creates a manual summary.
  const ManualSummary({
    required this.id,
    required this.title,
    required this.machine,
    required this.language,
    required this.documentCode,
    required this.procedureCount,
  });

  /// Pack identifier.
  final String id;

  /// Full title, usually "Machine — Unit".
  final String title;

  /// Machine model; empty when the pack names none.
  final String machine;

  /// Language code of the manual.
  final String language;

  /// Factory document number.
  final String documentCode;

  /// Number of procedures in the manual.
  final int procedureCount;

  /// Unit name: the title without the machine prefix.
  String get unitTitle {
    final parts = title.split(' — ');
    return parts.length > 1 ? parts.sublist(1).join(' — ') : title;
  }
}

/// Manuals of one machine.
final class MachineGroup {
  /// Creates a group.
  const MachineGroup({required this.machine, required this.manuals});

  /// Machine model; empty for packs without a machine.
  final String machine;

  /// Manuals of this machine.
  final List<ManualSummary> manuals;

  /// Value used in the route for this group.
  String get routeKey => machine.isEmpty ? '-' : machine;
}

/// Groups [manuals] by machine, sorted by name, packs without a machine last.
List<MachineGroup> groupByMachine(List<ManualSummary> manuals) {
  final byMachine = <String, List<ManualSummary>>{};
  for (final manual in manuals) {
    byMachine.putIfAbsent(manual.machine, () => []).add(manual);
  }
  final names = byMachine.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.compareTo(b);
    });
  return [
    for (final name in names)
      MachineGroup(machine: name, manuals: byMachine[name] ?? const []),
  ];
}

/// One procedure in a list.
final class ProcedureSummary {
  /// Creates a summary.
  const ProcedureSummary({
    required this.id,
    required this.code,
    required this.title,
  });

  /// Procedure identifier.
  final String id;

  /// Factory page code.
  final String code;

  /// Procedure title.
  final String title;
}

/// A section of a manual with its procedures.
final class ManualSection {
  /// Creates a section.
  const ManualSection({required this.title, required this.procedures});

  /// Section title.
  final String title;

  /// Procedures in manual order.
  final List<ProcedureSummary> procedures;
}

/// One search result.
final class SearchHit {
  /// Creates a hit.
  const SearchHit({
    required this.procedureId,
    required this.title,
    required this.location,
    required this.before,
    required this.match,
    required this.after,
  });

  /// Procedure identifier.
  final String procedureId;

  /// Procedure title.
  final String title;

  /// Manual title and page code.
  final String location;

  /// Fragment text before the matched word.
  final String before;

  /// The matched word.
  final String match;

  /// Fragment text after the matched word.
  final String after;
}

/// Result of importing one pack.
final class ImportedPack {
  /// Creates the result.
  const ImportedPack({required this.title, required this.procedureCount});

  /// Manual title.
  final String title;

  /// Number of imported procedures.
  final int procedureCount;
}
