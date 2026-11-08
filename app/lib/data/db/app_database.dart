import 'package:drift/drift.dart';
import 'package:engineer/data/db/tables.dart';

part 'app_database.g.dart';

/// The on-device store.
@DriftDatabase(
  tables: [
    Manuals,
    Procedures,
    ProcedureSearchDocs,
    PackImages,
    Reports,
    ReportMembers,
    ReportRecords,
    RecordDiscrepancies,
    OperationLog,
    AppSettings,
    ManualUnits,
    TechSpecs,
    MeasurementReadings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database over [executor].
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'CREATE VIRTUAL TABLE procedure_fts USING fts5( '
        "title, body, content='', contentless_delete=1, "
        "tokenize='unicode61 remove_diacritics 2')",
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(reports, reports.machine);
        await migrator.addColumn(reports, reports.manualId);
        await migrator.addColumn(reports, reports.unitCode);
        await migrator.addColumn(reports, reports.unitName);
        await migrator.addColumn(reports, reports.unitType);
        await migrator.addColumn(reports, reports.serialNo);
        await migrator.addColumn(reports, reports.customer);
        await migrator.createTable(manualUnits);
        await migrator.createTable(techSpecs);
        await migrator.createTable(measurementReadings);
        await migrator.createIndex(techSpecsManualIdx);
        await migrator.createIndex(readingsPointIdx);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
