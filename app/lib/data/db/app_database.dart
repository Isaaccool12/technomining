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
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database over [executor].
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'CREATE VIRTUAL TABLE procedure_fts USING fts5('
        "title, body, content='', contentless_delete=1, "
        "tokenize='unicode61 remove_diacritics 2')",
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
