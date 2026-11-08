import 'dart:io';

import 'package:drift/drift.dart';
import 'package:engineer/core/clock.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/core/search_text.dart';
import 'package:engineer/data/db/app_database.dart';
import 'package:engineer/data/pack/pack_reader.dart';
import 'package:engineer/data/pack/techdata_parser.dart';
import 'package:engineer/data/repositories/record_stamper.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/domain/library_repository.dart';
import 'package:path/path.dart' as p;

const int _searchLimit = 50;

/// [LibraryRepository] over the Drift database and pack files on disk.
final class DriftLibraryRepository implements LibraryRepository {
  /// Creates the repository; pack files live under [packsRoot].
  DriftLibraryRepository(this._db, Clock clock, this.packsRoot)
    : _stamper = RecordStamper(_db, clock);

  final AppDatabase _db;
  final RecordStamper _stamper;

  /// Directory holding `proc/`, `img/` and the page being viewed.
  final String packsRoot;

  @override
  Stream<List<ManualSummary>> watchManuals() {
    final query = _db.select(_db.manuals)
      ..where((m) => m.isDeleted.equals(false))
      ..orderBy([(m) => OrderingTerm.asc(m.title)]);
    return query.watch().map((rows) => rows.map(_toSummary).toList());
  }

  ManualSummary _toSummary(ManualRow row) => ManualSummary(
    id: row.id,
    title: row.title,
    machine: row.machine,
    language: row.lang,
    documentCode: row.docCode,
    procedureCount: row.procedureCount,
  );

  @override
  Future<List<ManualSection>> loadSections(String manualId) async {
    final query = _db.select(_db.procedures)
      ..where((t) => t.manualId.equals(manualId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    final rows = await query.get();
    final sections = <String, List<ProcedureSummary>>{};
    for (final row in rows) {
      sections
          .putIfAbsent(row.sectionTitle, () => [])
          .add(ProcedureSummary(id: row.id, code: row.code, title: row.title));
    }
    return [
      for (final entry in sections.entries)
        ManualSection(title: entry.key, procedures: entry.value),
    ];
  }

  @override
  Future<String?> procedureTitle(String procedureId) async {
    final row = await _findProcedure(procedureId);
    return row?.title;
  }

  Future<ProcedureRow?> _findProcedure(String procedureId) {
    final query = _db.select(_db.procedures)
      ..where((t) => t.id.equals(procedureId));
    return query.getSingleOrNull();
  }

  @override
  Future<Result<ImportedPack, ImportFailure>> importPack(String zipPath) async {
    final parsed = await readPack(zipPath, packsRoot);
    switch (parsed) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        return _store(value);
    }
  }

  Future<Result<ImportedPack, ImportFailure>> _store(ParsedPack pack) async {
    try {
      await _db.transaction(() async {
        await _deleteManual(pack.id);
        final stamp = await _stamper.nextStamp();
        await _insertManual(pack, stamp);
        for (final procedure in pack.procedures) {
          await _insertProcedure(pack.id, procedure, stamp);
        }
        await _insertImages(pack.imageNames);
        await _insertTechdata(pack);
        await _stamper.logOperation(
          stamp,
          entityType: 'manual',
          entityId: pack.id,
          operation: 'import',
          newValue: pack.title,
        );
      });
    } on Exception {
      return const Err(ImportFailure.storage);
    }
    return Ok(
      ImportedPack(title: pack.title, procedureCount: pack.procedures.length),
    );
  }

  Future<void> _deleteManual(String manualId) async {
    await _db.customStatement(
      'DELETE FROM procedure_fts WHERE rowid IN ( '
      'SELECT d.doc_id FROM procedure_search_docs d '
      'JOIN procedures p ON p.id = d.procedure_id WHERE p.manual_id = ?)',
      [manualId],
    );
    final query = _db.delete(_db.manuals)
      ..where((m) => m.id.equals(manualId));
    await query.go();
  }

  Future<void> _insertManual(ParsedPack pack, RecordStamp stamp) async {
    await _db
        .into(_db.manuals)
        .insert(
          ManualsCompanion.insert(
            id: pack.id,
            authorId: stamp.authorId,
            hlc: stamp.hlc,
            createdAtUtcMs: stamp.nowUtcMs,
            updatedAtUtcMs: stamp.nowUtcMs,
            title: pack.title,
            lang: pack.language,
            docCode: pack.documentCode,
            machine: pack.machine,
            aggCode: pack.aggregateCode,
            source: pack.source,
            procedureCount: pack.procedures.length,
          ),
        );
  }

  Future<void> _insertProcedure(
    String manualId,
    ParsedProcedure procedure,
    RecordStamp stamp,
  ) async {
    final id = '$manualId:${procedure.key}';
    await _db
        .into(_db.procedures)
        .insert(
          ProceduresCompanion.insert(
            id: id,
            authorId: stamp.authorId,
            hlc: stamp.hlc,
            createdAtUtcMs: stamp.nowUtcMs,
            updatedAtUtcMs: stamp.nowUtcMs,
            manualId: manualId,
            procKey: procedure.key,
            code: procedure.code,
            title: procedure.title,
            sectionTitle: procedure.sectionTitle,
            sortOrder: procedure.sortOrder,
            pageFrom: Value(procedure.pageFrom),
            pageTo: Value(procedure.pageTo),
            tier: Value(procedure.tier),
          ),
        );
    final docId = await _db
        .into(_db.procedureSearchDocs)
        .insert(
          ProcedureSearchDocsCompanion.insert(
            procedureId: id,
            rawText: procedure.rawText,
          ),
        );
    await _db.customStatement(
      'INSERT INTO procedure_fts(rowid, title, body) VALUES (?, ?, ?)',
      [docId, procedure.titleIndex, procedure.bodyIndex],
    );
  }

  Future<void> _insertTechdata(ParsedPack pack) async {
    await _db.batch((batch) {
      batch
        ..insertAll(_db.manualUnits, [
          for (var i = 0; i < pack.units.length; i++)
            ManualUnitsCompanion.insert(
              manualId: pack.id,
              code: pack.units[i].code,
              name: pack.units[i].name,
              unitType: pack.units[i].unitType,
              sortOrder: i,
            ),
        ], mode: InsertMode.insertOrIgnore)
        ..insertAll(_db.techSpecs, [
          for (var i = 0; i < pack.specs.length; i++)
            _specCompanion(pack.id, pack.specs[i], i),
        ]);
    });
  }

  TechSpecsCompanion _specCompanion(String manualId, ParsedSpec spec, int i) =>
      TechSpecsCompanion.insert(
        id: '$manualId:${spec.key}',
        manualId: manualId,
        kind: spec.isTorque ? 'torque' : 'spec',
        name: spec.name,
        unit: spec.unit,
        nominal: Value(spec.nominal),
        minValue: Value(spec.min),
        maxValue: Value(spec.max),
        limitValue: Value(spec.limit),
        specKind: Value(spec.specKind),
        note: Value(spec.note),
        torqueText: Value(spec.torqueText),
        procKey: spec.procKey,
        procTitle: spec.procTitle,
        procCode: spec.procCode,
        page: Value(spec.page),
        unitCodes: ',${spec.unitCodes.join(',')},',
        sortOrder: i,
      );

  Future<void> _insertImages(List<String> names) async {
    await _db.batch((batch) {
      batch.insertAll(
        _db.packImages,
        [for (final name in names) PackImagesCompanion.insert(name: name)],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    final match = buildMatchExpression(query);
    if (match == null) return const [];
    final rows = await _db
        .customSelect(
          'SELECT p.id, p.title, p.code, m.title AS manual_title, d.raw_text '
          'FROM procedure_fts '
          'JOIN procedure_search_docs d ON d.doc_id = procedure_fts.rowid '
          'JOIN procedures p ON p.id = d.procedure_id '
          'JOIN manuals m ON m.id = p.manual_id '
          'WHERE procedure_fts MATCH ? AND p.is_deleted = 0 AND m.is_deleted = 0 '
          'ORDER BY bm25(procedure_fts, 10.0, 1.0) LIMIT ?',
          variables: [
            Variable.withString(match),
            Variable.withInt(_searchLimit),
          ],
        )
        .get();
    final stems = queryStems(query);
    return rows.map((row) => _toHit(row, stems)).toList();
  }

  SearchHit _toHit(QueryRow row, List<String> stems) {
    final snippet = buildSnippet(row.read<String>('raw_text'), stems);
    return SearchHit(
      procedureId: row.read<String>('id'),
      title: row.read<String>('title'),
      location: '${row.read<String>('manual_title')} · ${row.read<String>('code')}',
      before: snippet.before,
      match: snippet.match,
      after: snippet.after,
    );
  }

  @override
  Future<Result<String, ProcedureViewFailure>> prepareProcedureView(
    String procedureId, {
    required bool isDark,
  }) async {
    final row = await _findProcedure(procedureId);
    if (row == null) return const Err(ProcedureViewFailure.missing);
    final body = File(
      p.join(
        packsRoot,
        'proc',
        manualDirectoryName(row.manualId),
        '${row.procKey}.html',
      ),
    );
    if (!body.existsSync()) return const Err(ProcedureViewFailure.missing);
    final page = wrapProcedureHtml(await body.readAsString(), isDark: isDark);
    final target = File(p.join(packsRoot, 'view.html'));
    await target.writeAsString(page, flush: true);
    return Ok(target.path);
  }
}

/// Wraps a procedure [body] into a standalone offline page.
String wrapProcedureHtml(String body, {required bool isDark}) {
  final background = isDark ? '#14171a' : '#ffffff';
  final foreground = isDark ? '#e8eaed' : '#1a1c1e';
  final border = isDark ? '#5f6368' : '#9aa0a6';
  return '''
<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html{-webkit-text-size-adjust:100%}
body{margin:16px;font:18px/1.5 sans-serif;background:$background;color:$foreground}
h2{font-size:24px;line-height:1.25}
.kp-src{font-size:15px;opacity:.75}
img{max-width:100%;height:auto;background:#fff}
figure{margin:12px 0}
figcaption{font-size:14px;opacity:.75}
table{border-collapse:collapse;display:block;overflow-x:auto;max-width:100%}
td,th{border:1px solid $border;padding:8px;min-width:48px}
</style></head><body>$body</body></html>''';
}
