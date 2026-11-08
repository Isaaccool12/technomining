import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:engineer/core/clock.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/data/db/app_database.dart';
import 'package:engineer/data/repositories/record_stamper.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/report_repository.dart';
import 'package:engineer/features/reports/domain/report_templates.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Refused change inside a transaction; turned into a [ReportFailure].
final class _Refused implements Exception {
  const _Refused(this.failure);

  final ReportFailure failure;
}

/// [ReportRepository] over the Drift database; photos are files under
/// [photosRoot].
final class DriftReportRepository implements ReportRepository {
  /// Creates the repository.
  DriftReportRepository(
    this._db,
    Clock clock, {
    required this.photosRoot,
    required this.exportsDirectory,
  }) : _stamper = RecordStamper(_db, clock);

  final AppDatabase _db;
  final RecordStamper _stamper;

  /// Directory holding photo files, one folder per report.
  final String photosRoot;

  @override
  final String exportsDirectory;

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    final updates = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.reports,
        _db.reportRecords,
        _db.measurementReadings,
      ]),
    );
    await for (final _ in updates) {
      yield await load();
    }
  }

  @override
  Stream<List<ReportSummary>> watchReports() => _watch(_loadSummaries);

  @override
  Stream<ReportDetail?> watchReport(String reportId) =>
      _watch(() => _loadDetail(reportId));

  Future<List<ReportSummary>> _loadSummaries() async {
    final query = _db.select(_db.reports)
      ..where((r) => r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.desc(r.updatedAtUtcMs)]);
    final rows = await query.get();
    final summaries = <ReportSummary>[];
    for (final row in rows) {
      final detail = await _detailOf(row);
      final points = detail.nodes.expand((n) => n.points);
      summaries.add(
        ReportSummary(
          header: detail.header,
          measured: points.where((pt) => pt.latest != null).length,
          outside: points
              .where((pt) => pt.status == ToleranceStatus.outside)
              .length,
        ),
      );
    }
    return summaries;
  }

  Future<ReportDetail?> _loadDetail(String reportId) async {
    final row = await _findReport(reportId);
    return row == null ? null : _detailOf(row);
  }

  Future<ReportRow?> _findReport(String reportId) {
    final query = _db.select(_db.reports)
      ..where((r) => r.id.equals(reportId) & r.isDeleted.equals(false));
    return query.getSingleOrNull();
  }

  ReportHeader _header(ReportRow row) => ReportHeader(
    id: row.id,
    type: ReportType.fromCode(row.reportType),
    status: ReportStatus.fromCode(row.status),
    title: row.title,
    machine: row.machine,
    manualId: row.manualId,
    unitCode: row.unitCode,
    unitName: row.unitName,
    unitType: row.unitType,
    serialNo: row.serialNo,
    customer: row.customer,
    authorId: row.authorId,
    createdAtUtcMs: row.createdAtUtcMs,
    updatedAtUtcMs: row.updatedAtUtcMs,
  );

  Future<ReportDetail> _detailOf(ReportRow row) async {
    final recordQuery = _db.select(_db.reportRecords)
      ..where((r) => r.reportId.equals(row.id) & r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.asc(r.hlc)]);
    final records = await recordQuery.get();
    final readingQuery = _db.select(_db.measurementReadings)
      ..where((r) => r.reportId.equals(row.id) & r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.desc(r.hlc)]);
    final readings = <String, List<Reading>>{};
    for (final reading in await readingQuery.get()) {
      readings
          .putIfAbsent(reading.pointId, () => [])
          .add(
            Reading(
              valueText: reading.valueText,
              authorId: reading.authorId,
              atUtcMs: reading.createdAtUtcMs,
            ),
          );
    }
    final children = <String, List<ReportRecordRow>>{};
    for (final record in records) {
      final parent = record.parentRecordId;
      if (parent != null) children.putIfAbsent(parent, () => []).add(record);
    }
    final nodes = [
      for (final record in records)
        if (record.kind == 'node')
          _node(record, children[record.id] ?? const [], readings),
    ];
    return ReportDetail(header: _header(row), nodes: nodes);
  }

  ReportNode _node(
    ReportRecordRow record,
    List<ReportRecordRow> children,
    Map<String, List<Reading>> readings,
  ) {
    final payload = _payload(record);
    final remarks = children.where((c) => c.kind == 'remark');
    return ReportNode(
      id: record.id,
      title: _text(payload, 'title'),
      procCode: _text(payload, 'procCode'),
      remark: remarks.isEmpty ? '' : _text(_payload(remarks.last), 'text'),
      points: [
        for (final child in children)
          if (child.kind == 'measurement')
            _point(child, readings[child.id] ?? const []),
      ],
      photos: [
        for (final child in children)
          if (child.kind == 'photo') _photo(child),
      ],
    );
  }

  MeasurementPoint _point(ReportRecordRow record, List<Reading> readings) {
    final payload = _payload(record);
    return MeasurementPoint(
      id: record.id,
      name: _text(payload, 'name'),
      tolerance: Tolerance(
        unit: _text(payload, 'unit'),
        nominal: _number(payload['nom']),
        min: _number(payload['min']),
        max: _number(payload['max']),
        limit: _number(payload['limit']),
      ),
      readings: readings,
    );
  }

  ReportPhoto _photo(ReportRecordRow record) {
    final payload = _payload(record);
    final annotated = _text(payload, 'annotated');
    final pointId = _text(payload, 'pointId');
    final marks = payload['marks'];
    return ReportPhoto(
      id: record.id,
      originalPath: p.join(photosRoot, _text(payload, 'original')),
      annotatedPath: annotated.isEmpty ? null : p.join(photosRoot, annotated),
      caption: _text(payload, 'caption'),
      marks: marks is List<dynamic>
          ? marks.map(parsePhotoMark).whereType<PhotoMark>().toList()
          : const [],
      pointId: pointId.isEmpty ? null : pointId,
    );
  }

  @override
  Future<List<UnitOption>> unitOptions() async {
    final rows = await _db
        .customSelect(
          'SELECT u.manual_id, m.machine, u.code, u.name, u.unit_type, '
          '(SELECT COUNT(*) FROM tech_specs s WHERE s.manual_id = u.manual_id '
          "AND s.kind = 'spec' AND s.unit_codes LIKE '%,' || u.code || ',%') "
          'AS spec_count '
          'FROM manual_units u JOIN manuals m ON m.id = u.manual_id '
          'WHERE m.is_deleted = 0 ORDER BY m.machine, m.title, u.sort_order',
        )
        .get();
    return [
      for (final row in rows)
        UnitOption(
          manualId: row.read<String>('manual_id'),
          machine: row.read<String>('machine'),
          code: row.read<String>('code'),
          name: row.read<String>('name'),
          unitType: row.read<String>('unit_type'),
          specCount: row.read<int>('spec_count'),
        ),
    ];
  }

  @override
  Future<List<TechSpec>> unitSpecs(String manualId, String unitCode) async {
    final query = _db.select(_db.techSpecs)
      ..where(
        (s) =>
            s.manualId.equals(manualId) & s.unitCodes.like('%,$unitCode,%'),
      )
      ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]);
    final rows = await query.get();
    return [
      for (final row in rows)
        TechSpec(
          id: row.id,
          name: row.name,
          tolerance: Tolerance(
            unit: row.unit,
            nominal: row.nominal,
            min: row.minValue,
            max: row.maxValue,
            limit: row.limitValue,
          ),
          isTorque: row.kind == 'torque',
          torqueText: row.torqueText,
          procKey: row.procKey,
          procTitle: row.procTitle,
          procCode: row.procCode,
          page: row.page,
        ),
    ];
  }

  @override
  Future<Result<String, ReportFailure>> createReport(NewReport data) async {
    final unit = data.unit;
    final available = unit == null
        ? const <TechNode>[]
        : groupTechNodes(await unitSpecs(unit.manualId, unit.code));
    final template = templateFor(data.type);
    final techNodes = techNodesFor(
      template,
      available,
      data.selectedProcKeys,
    );
    final reportId = const Uuid().v4();
    final unitLabel = unit?.name ?? '';
    final title = [
      data.type.label,
      if (unitLabel.isNotEmpty) unitLabel,
      if (data.serialNo.trim().isNotEmpty) '№ ${data.serialNo.trim()}',
    ].join(' · ');
    return _guard(() async {
      final stamp = await _stamper.nextStamp();
      await _db
          .into(_db.reports)
          .insert(
            ReportsCompanion.insert(
              id: reportId,
              authorId: stamp.authorId,
              hlc: stamp.hlc,
              createdAtUtcMs: stamp.nowUtcMs,
              updatedAtUtcMs: stamp.nowUtcMs,
              reportType: data.type.code,
              title: title,
              machine: Value(data.machine.trim()),
              manualId: Value(unit?.manualId),
              unitCode: Value(unit?.code ?? ''),
              unitName: Value(unitLabel),
              unitType: Value(unit?.unitType ?? ''),
              serialNo: Value(data.serialNo.trim()),
              customer: Value(data.customer.trim()),
            ),
          );
      await _db
          .into(_db.reportMembers)
          .insert(
            ReportMembersCompanion.insert(
              id: const Uuid().v4(),
              authorId: stamp.authorId,
              hlc: stamp.hlc,
              createdAtUtcMs: stamp.nowUtcMs,
              updatedAtUtcMs: stamp.nowUtcMs,
              reportId: reportId,
              userId: stamp.authorId,
              role: 'author',
            ),
          );
      await _stamper.logOperation(
        stamp,
        entityType: 'report',
        entityId: reportId,
        operation: 'insert',
        newValue: title,
      );
      for (final name in template.leadingNodes) {
        await _insertNode(reportId, name, null);
      }
      for (final node in techNodes) {
        await _insertNode(reportId, node.title, node);
      }
      for (final name in template.trailingNodes) {
        await _insertNode(reportId, name, null);
      }
      return reportId;
    });
  }

  Future<String> _insertNode(
    String reportId,
    String title,
    TechNode? from,
  ) async {
    final nodeId = await _insertRecord(reportId, 'node', {
      'title': title,
      if (from != null) 'procKey': from.procKey,
      if (from != null) 'procCode': from.code,
    });
    for (final spec in from?.specs ?? const <TechSpec>[]) {
      await _insertRecord(
        reportId,
        'measurement',
        _pointPayload(spec.name, spec),
        parentId: nodeId,
      );
    }
    return nodeId;
  }

  Map<String, Object?> _pointPayload(String name, TechSpec? spec) => {
    'name': name,
    'unit': spec?.tolerance.unit ?? 'мм',
    if (spec?.tolerance.nominal != null) 'nom': spec?.tolerance.nominal,
    if (spec?.tolerance.min != null) 'min': spec?.tolerance.min,
    if (spec?.tolerance.max != null) 'max': spec?.tolerance.max,
    if (spec?.tolerance.limit != null) 'limit': spec?.tolerance.limit,
    if (spec != null) 'specId': spec.id,
  };

  Future<String> _insertRecord(
    String reportId,
    String kind,
    Map<String, Object?> payload, {
    String? parentId,
  }) async {
    final stamp = await _stamper.nextStamp();
    final id = const Uuid().v4();
    final json = jsonEncode(payload);
    await _db
        .into(_db.reportRecords)
        .insert(
          ReportRecordsCompanion.insert(
            id: id,
            authorId: stamp.authorId,
            hlc: stamp.hlc,
            createdAtUtcMs: stamp.nowUtcMs,
            updatedAtUtcMs: stamp.nowUtcMs,
            reportId: reportId,
            parentRecordId: Value(parentId),
            kind: kind,
            payloadJson: json,
          ),
        );
    await _stamper.logOperation(
      stamp,
      entityType: 'report_record',
      entityId: id,
      operation: 'insert',
      newValue: json,
    );
    await _touch(reportId, stamp);
    return id;
  }

  Future<void> _updateRecord(
    String reportId,
    String recordId,
    Map<String, Object?> Function(Map<String, dynamic> old) change,
  ) async {
    final query = _db.select(_db.reportRecords)
      ..where((r) => r.id.equals(recordId) & r.reportId.equals(reportId));
    final row = await query.getSingleOrNull();
    if (row == null) throw const _Refused(ReportFailure.missing);
    final json = jsonEncode(change(_payload(row)));
    final stamp = await _stamper.nextStamp();
    final update = _db.update(_db.reportRecords)
      ..where((r) => r.id.equals(recordId));
    await update.write(
      ReportRecordsCompanion(
        payloadJson: Value(json),
        hlc: Value(stamp.hlc),
        updatedAtUtcMs: Value(stamp.nowUtcMs),
      ),
    );
    await _stamper.logOperation(
      stamp,
      entityType: 'report_record',
      entityId: recordId,
      operation: 'update',
      oldValue: row.payloadJson,
      newValue: json,
    );
    await _touch(reportId, stamp);
  }

  Future<void> _touch(String reportId, RecordStamp stamp) async {
    final update = _db.update(_db.reports)..where((r) => r.id.equals(reportId));
    await update.write(
      ReportsCompanion(
        hlc: Value(stamp.hlc),
        updatedAtUtcMs: Value(stamp.nowUtcMs),
      ),
    );
  }

  /// Runs [body] in one transaction; a refusal or a storage error becomes a
  /// typed failure and nothing is written.
  Future<Result<T, ReportFailure>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await _db.transaction(body));
    } on _Refused catch (refused) {
      return Err(refused.failure);
    } on Exception {
      return const Err(ReportFailure.storage);
    }
  }

  /// Like [_guard], but only while the report is a draft.
  Future<Result<T, ReportFailure>> _edit<T>(
    String reportId,
    Future<T> Function() body,
  ) => _guard(() async {
    final row = await _findReport(reportId);
    if (row == null) throw const _Refused(ReportFailure.missing);
    if (!ReportStatus.fromCode(row.status).isEditable) {
      throw const _Refused(ReportFailure.locked);
    }
    return body();
  });

  @override
  Future<Result<String, ReportFailure>> addNode(
    String reportId,
    String title, {
    TechNode? from,
  }) => _edit(reportId, () => _insertNode(reportId, title, from));

  @override
  Future<Result<String, ReportFailure>> addPoint(
    String reportId,
    String nodeId,
    String name,
    TechSpec? spec,
  ) => _edit(
    reportId,
    () => _insertRecord(
      reportId,
      'measurement',
      _pointPayload(name, spec),
      parentId: nodeId,
    ),
  );

  @override
  Future<Result<void, ReportFailure>> addReading(
    String reportId,
    String pointId,
    String typed,
  ) async {
    final canonical = canonicalDecimal(typed);
    if (canonical == null) return const Err(ReportFailure.notNumber);
    return _edit(reportId, () async {
      final stamp = await _stamper.nextStamp();
      final id = const Uuid().v4();
      await _db
          .into(_db.measurementReadings)
          .insert(
            MeasurementReadingsCompanion.insert(
              id: id,
              authorId: stamp.authorId,
              hlc: stamp.hlc,
              createdAtUtcMs: stamp.nowUtcMs,
              updatedAtUtcMs: stamp.nowUtcMs,
              reportId: reportId,
              pointId: pointId,
              valueText: canonical,
            ),
          );
      await _stamper.logOperation(
        stamp,
        entityType: 'reading',
        entityId: id,
        operation: 'insert',
        field: pointId,
        newValue: canonical,
      );
      await _touch(reportId, stamp);
    });
  }

  @override
  Future<Result<void, ReportFailure>> setRemark(
    String reportId,
    String nodeId,
    String text,
  ) => _edit(reportId, () async {
    final query = _db.select(_db.reportRecords)
      ..where(
        (r) =>
            r.parentRecordId.equals(nodeId) &
            r.kind.equals('remark') &
            r.isDeleted.equals(false),
      );
    final existing = await query.get();
    if (existing.isEmpty) {
      if (text.trim().isEmpty) return;
      await _insertRecord(reportId, 'remark', {'text': text}, parentId: nodeId);
    } else {
      await _updateRecord(reportId, existing.last.id, (_) => {'text': text});
    }
  });

  Future<String?> _savePng(String reportId, PhotoInput input) async {
    final png = input.annotatedPng;
    if (png == null) return null;
    final name = p.join(reportId, '${const Uuid().v4()}_marks.png');
    final file = File(p.join(photosRoot, name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png, flush: true);
    return name;
  }

  Map<String, Object?> _photoPayload(
    String original,
    String? annotated,
    PhotoInput input,
  ) => {
    'original': original,
    if (annotated != null) 'annotated': annotated,
    'caption': input.caption,
    'marks': [for (final mark in input.marks) mark.toJson()],
    if (input.pointId != null) 'pointId': input.pointId,
  };

  @override
  Future<Result<String, ReportFailure>> addPhoto(
    String reportId,
    String nodeId,
    String sourcePath,
    PhotoInput input,
  ) async {
    final String original;
    final String? annotated;
    try {
      final extension = p.extension(sourcePath).toLowerCase();
      original = p.join(
        reportId,
        '${const Uuid().v4()}${extension.isEmpty ? '.jpg' : extension}',
      );
      final target = File(p.join(photosRoot, original));
      await target.parent.create(recursive: true);
      await File(sourcePath).copy(target.path);
      annotated = await _savePng(reportId, input);
    } on FileSystemException {
      return const Err(ReportFailure.storage);
    }
    return _edit(
      reportId,
      () => _insertRecord(
        reportId,
        'photo',
        _photoPayload(original, annotated, input),
        parentId: nodeId,
      ),
    );
  }

  @override
  Future<Result<void, ReportFailure>> updatePhoto(
    String reportId,
    String photoId,
    PhotoInput input,
  ) async {
    final String? annotated;
    try {
      annotated = await _savePng(reportId, input);
    } on FileSystemException {
      return const Err(ReportFailure.storage);
    }
    return _edit(
      reportId,
      () => _updateRecord(
        reportId,
        photoId,
        (old) => _photoPayload(_text(old, 'original'), annotated, input),
      ),
    );
  }

  @override
  Future<Result<void, ReportFailure>> removeRecord(
    String reportId,
    String recordId,
  ) => _edit(reportId, () async {
    final stamp = await _stamper.nextStamp();
    final update = _db.update(_db.reportRecords)
      ..where((r) => r.id.equals(recordId) & r.reportId.equals(reportId));
    final count = await update.write(
      ReportRecordsCompanion(
        isDeleted: const Value(true),
        hlc: Value(stamp.hlc),
        updatedAtUtcMs: Value(stamp.nowUtcMs),
      ),
    );
    if (count == 0) throw const _Refused(ReportFailure.missing);
    await _stamper.logOperation(
      stamp,
      entityType: 'report_record',
      entityId: recordId,
      operation: 'delete',
    );
    await _touch(reportId, stamp);
  });

  @override
  Future<Result<void, ReportFailure>> setStatus(
    String reportId,
    ReportStatus status,
  ) => _guard(() async {
    final row = await _findReport(reportId);
    if (row == null) throw const _Refused(ReportFailure.missing);
    final from = ReportStatus.fromCode(row.status);
    if (!canMoveStatus(from, status)) {
      throw const _Refused(ReportFailure.badTransition);
    }
    final stamp = await _stamper.nextStamp();
    final update = _db.update(_db.reports)..where((r) => r.id.equals(reportId));
    await update.write(
      ReportsCompanion(
        status: Value(status.code),
        hlc: Value(stamp.hlc),
        updatedAtUtcMs: Value(stamp.nowUtcMs),
      ),
    );
    await _stamper.logOperation(
      stamp,
      entityType: 'report',
      entityId: reportId,
      operation: 'update',
      field: 'status',
      oldValue: from.code,
      newValue: status.code,
    );
  });
}

Map<String, dynamic> _payload(ReportRecordRow row) {
  try {
    final decoded = jsonDecode(row.payloadJson);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

String _text(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value : '';
}

double? _number(Object? value) => value is num ? value.toDouble() : null;
