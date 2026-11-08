// Table columns are named by the schema; docs would only repeat the names.
// ignore_for_file: public_member_api_docs

import 'package:drift/drift.dart';

/// Columns every merge-ready record carries.
mixin AuditColumns on Table {
  TextColumn get id => text()();
  TextColumn get authorId => text()();
  TextColumn get hlc => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();
}

@DataClassName('ManualRow')
class Manuals extends Table with AuditColumns {
  TextColumn get title => text()();
  TextColumn get lang => text()();
  TextColumn get docCode => text()();
  TextColumn get machine => text()();
  TextColumn get aggCode => text()();
  TextColumn get source => text()();
  IntColumn get procedureCount => integer()();

  /// Hash of the pack, for updates that fetch only the difference.
  TextColumn get sha => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  bool get isStrict => true;
}

@DataClassName('ProcedureRow')
@TableIndex(name: 'procedures_manual_idx', columns: {#manualId, #sortOrder})
class Procedures extends Table with AuditColumns {
  TextColumn get manualId =>
      text().references(Manuals, #id, onDelete: KeyAction.cascade)();
  TextColumn get procKey => text()();
  TextColumn get code => text()();
  TextColumn get title => text()();
  TextColumn get sectionTitle => text()();
  IntColumn get sortOrder => integer()();
  IntColumn get pageFrom => integer().nullable()();
  IntColumn get pageTo => integer().nullable()();
  TextColumn get tier => text().withDefault(const Constant('local'))();

  /// Hash of the body, for updates that fetch only the difference.
  TextColumn get sha => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {manualId, procKey},
  ];

  @override
  List<String> get customConstraints => const [
    "CHECK (tier IN ('local', 'online'))",
  ];

  @override
  bool get isStrict => true;
}

/// Source text of a procedure; its [docId] is the rowid in the FTS5 index.
@DataClassName('ProcedureSearchDocRow')
class ProcedureSearchDocs extends Table {
  IntColumn get docId => integer().autoIncrement()();
  TextColumn get procedureId =>
      text().unique().references(Procedures, #id, onDelete: KeyAction.cascade)();
  TextColumn get rawText => text()();

  @override
  bool get isStrict => true;
}

/// Images shared by all packs, stored once by file name.
@DataClassName('PackImageRow')
class PackImages extends Table {
  TextColumn get name => text()();
  TextColumn get sha => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {name};

  @override
  bool get isStrict => true;
}

@DataClassName('ReportRow')
class Reports extends Table with AuditColumns {
  TextColumn get reportType => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get title => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (report_type IN ('full', 'partial', 'field', 'arrival'))",
    "CHECK (status IN ('draft', 'review', 'approved'))",
  ];

  @override
  bool get isStrict => true;
}

@DataClassName('ReportMemberRow')
@TableIndex(name: 'report_members_report_idx', columns: {#reportId})
class ReportMembers extends Table with AuditColumns {
  TextColumn get reportId =>
      text().references(Reports, #id, onDelete: KeyAction.restrict)();
  TextColumn get userId => text()();
  TextColumn get role => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (role IN ('author', 'member'))",
  ];

  @override
  bool get isStrict => true;
}

/// A small report entry: node, measurement, photo, remark or inspection mark.
@DataClassName('ReportRecordRow')
@TableIndex(name: 'report_records_report_idx', columns: {#reportId, #kind})
class ReportRecords extends Table with AuditColumns {
  TextColumn get reportId =>
      text().references(Reports, #id, onDelete: KeyAction.restrict)();
  TextColumn get parentRecordId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (kind IN ('node', 'measurement', 'photo', 'remark', 'inspected'))",
  ];

  @override
  bool get isStrict => true;
}

/// A losing value kept for the "Расхождения" list.
@DataClassName('RecordDiscrepancyRow')
@TableIndex(name: 'record_discrepancies_report_idx', columns: {#reportId})
class RecordDiscrepancies extends Table with AuditColumns {
  TextColumn get reportId =>
      text().references(Reports, #id, onDelete: KeyAction.restrict)();
  TextColumn get recordId => text()();
  TextColumn get field => text().nullable()();
  TextColumn get losingValue => text().nullable()();
  TextColumn get losingAuthorId => text()();
  TextColumn get losingHlc => text()();
  IntColumn get resolvedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  bool get isStrict => true;
}

/// Journal of changes: who, what, when, old and new value.
@DataClassName('OperationRow')
@TableIndex(name: 'operation_log_entity_idx', columns: {#entityType, #entityId})
@TableIndex(name: 'operation_log_hlc_idx', columns: {#hlc})
class OperationLog extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get field => text().nullable()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get authorId => text()();
  TextColumn get hlc => text()();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get syncedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (operation IN ('insert', 'update', 'delete', 'restore', 'import'))",
  ];

  @override
  bool get isStrict => true;
}

@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};

  @override
  bool get isStrict => true;
}
