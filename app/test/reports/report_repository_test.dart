import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:engineer/core/clock.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/data/db/app_database.dart';
import 'package:engineer/data/repositories/drift_library_repository.dart';
import 'package:engineer/data/repositories/drift_report_repository.dart';
import 'package:engineer/features/reports/application/report_pdf.dart';
import 'package:engineer/features/reports/application/report_print.dart';
import 'package:engineer/features/reports/domain/grid.dart';
import 'package:engineer/features/reports/domain/inspection.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/report_repository.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _StepClock implements Clock {
  int _now = 1794147941000;

  @override
  int nowUtcMs() => _now += 1000;
}

void _add(Archive archive, String name, Object json) {
  final bytes = utf8.encode(jsonEncode(json));
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

/// A machine book like `HD785-7_book_app.zip`: two units, labelled specs.
File _writeBook(Directory dir) {
  final archive = Archive();
  _add(archive, 'index.json', {
    'format': 'qs-manual-pack',
    'version': 1,
    'manual': {
      'id': 'SRU05900-01-book',
      'title': 'HD785-7 — Заводская инструкция',
      'lang': 'ru',
      'doc': 'SRU05900-01',
      'machine': 'HD785-7',
      'agg': 'book',
      'source': 'komatsu-pdf',
      'aggs': [
        {'code': 'eng', 'name': 'Двигатель', 'type': 'ДВС'},
        {'code': 'trans', 'name': 'Коробка передач', 'type': 'КПП'},
      ],
    },
    'sections': [
      {
        'title': '10 Нормативы',
        'procs': ['k90', 'k108'],
      },
    ],
    'procs': {
      'k90': {'code': '10-90', 'title': 'Выходной вал', 'pages': [90, 91]},
      'k108': {'code': '10-108', 'title': 'Коробка передач', 'pages': [108]},
    },
  });
  _add(archive, 'search.json', {'k90': 'Выходной вал', 'k108': 'Коробка'});
  _add(archive, 'techdata.json', {
    'specs': [
      {
        'name': 'Вал',
        'unit': 'мм',
        'nom': 170.0,
        'min': 169.975,
        'max': 170.0,
        'proc': 'k90',
        'title': 'Выходной вал',
        'code': '10-90',
        'aggs': ['trans'],
      },
      {
        'name': 'Толщина упорной шайбы',
        'unit': 'мм',
        'nom': 3.0,
        'min': 2.5,
        'max': 3.1,
        'limit': 2.5,
        'proc': 'k108',
        'title': 'Коробка передач',
        'code': '10-108',
        'aggs': ['trans'],
      },
      {
        'name': 'Зазор клапана',
        'unit': 'мм',
        'min': 0.3,
        'max': 0.4,
        'proc': 'k90',
        'title': 'Выходной вал',
        'code': '10-90',
        'aggs': ['eng'],
      },
    ],
    'torques': [
      {
        'nm': '14,7–34',
        'op': 'по рисунку',
        'proc': 'k90',
        'title': 'Выходной вал',
        'code': '10-90',
        'aggs': ['trans'],
      },
    ],
  });
  return File(p.join(dir.path, 'book.zip'))
    ..writeAsBytesSync(ZipEncoder().encode(archive));
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late DriftReportRepository reports;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('engineer_reports');
    database = AppDatabase(NativeDatabase.memory());
    final clock = _StepClock();
    final library = DriftLibraryRepository(
      database,
      clock,
      p.join(directory.path, 'packs'),
    );
    await library.importPack(_writeBook(directory).path);
    reports = DriftReportRepository(
      database,
      clock,
      photosRoot: p.join(directory.path, 'photos'),
      exportsDirectory: p.join(directory.path, 'exports'),
    );
  });

  tearDown(() async {
    await database.close();
    directory.deleteSync(recursive: true);
  });

  Future<ReportDetail> createFull() async {
    final units = await reports.unitOptions();
    final trans = units.firstWhere((u) => u.code == 'trans');
    final created = await reports.createReport(
      NewReport(
        type: ReportType.full,
        machine: 'HD785-7 № 12',
        unit: trans,
        serialNo: '1234',
        customer: '',
        selectedProcKeys: const {},
      ),
    );
    final id = (created as Ok<String, ReportFailure>).value;
    return (await reports.watchReport(id).first)!;
  }

  test('units of a book come with the number of their tolerances', () async {
    final units = await reports.unitOptions();
    expect(units.map((u) => (u.code, u.specCount)), [('eng', 1), ('trans', 2)]);
    final specs = await reports.unitSpecs('SRU05900-01-book', 'trans');
    expect(specs.where((s) => s.isTorque), hasLength(1));
  });

  test('full disassembly gets the template and the unit tolerances', () async {
    final detail = await createFull();
    expect(detail.nodes.map((n) => n.title), [
      'Приёмочный осмотр',
      'Разборка и неисправности',
      'Выходной вал',
      'Коробка передач',
      'Сборка и испытания',
    ]);
    final shaft = detail.nodes[2].points.single;
    expect(shaft.name, 'Вал');
    expect(shaft.tolerance.min, 169.975);
    expect(detail.header.title, 'Полная разборка · Коробка передач · № 1234');
  });

  test('readings are kept as history and checked', () async {
    var detail = await createFull();
    final pointId = detail.nodes[2].points.single.id;
    final id = detail.header.id;
    expect(await reports.addReading(id, pointId, 'abc'), isA<Err<void, ReportFailure>>());
    await reports.addReading(id, pointId, '169,970');
    await reports.addReading(id, pointId, '169,99');
    detail = (await reports.watchReport(id).first)!;
    final point = detail.nodes[2].points.single;
    expect(point.readings, hasLength(2));
    expect(point.latest?.valueText, '169.99');
    expect(point.status, ToleranceStatus.within);
  });

  test('inspection sheet is seeded, marked and printed when inspected', () async {
    var detail = await createFull();
    final id = detail.header.id;
    final node = detail.nodes.first;
    expect(node.inspection, isNotEmpty);
    expect(node.inspection.every((i) => i.isStandard), isTrue);
    final first = node.inspection.first;
    await reports.saveInspectionItem(
      id,
      InspectionItem(
        id: first.id,
        name: first.name,
        isStandard: true,
        conditions: const {InspectionCondition.crack},
        actions: const {InspectionAction.replace},
      ),
    );
    detail = (await reports.watchReport(id).first)!;
    expect(printableReport(detail).nodes.first.inspection, hasLength(1));
    await reports.markRestClean(id, node.id);
    detail = (await reports.watchReport(id).first)!;
    final items = detail.nodes.first.inspection;
    expect(items.first.conditions, {InspectionCondition.crack});
    expect(items.skip(1).every((i) => i.isClean), isTrue);
  });

  test('grid keeps cells, derives grades and honours a manual one', () async {
    var detail = await createFull();
    final id = detail.header.id;
    final nodeId = detail.nodes[1].id;
    await reports.setComposition(id, (cylinders: 6, mains: 7));
    final added = await reports.addGrid(
      id,
      nodeId,
      'Коренная шейка',
      GridPreset.mainJournal.spec(6, 7),
      const Tolerance(unit: 'мм', nominal: 110, min: 109.98, max: 110),
    );
    final pointId = (added as Ok<String, ReportFailure>).value;
    await reports.addCellReading(id, pointId, gridCellKey(0, 0, 0), '109,8');
    await reports.addCellReading(id, pointId, gridCellKey(0, 0, 1), '109,99');
    detail = (await reports.watchReport(id).first)!;
    expect(detail.composition?.mains, 7);
    var point = detail.nodes[1].points.single;
    expect(point.grid?.rowCount, 7);
    expect(point.autoGrade(0)?.grade, PartGrade.repair);
    expect(point.autoGrade(0)?.repairStep, 0.25);
    expect(point.status, ToleranceStatus.outside);
    final grid = printableReport(detail).nodes
        .expand((n) => n.grids)
        .single;
    expect(grid.rows, hasLength(1));
    await reports.setGrade(id, pointId, 0, PartGrade.replace);
    detail = (await reports.watchReport(id).first)!;
    point = detail.nodes[1].points.single;
    expect(point.gradeOf(0)?.grade, PartGrade.replace);
    await reports.setGrade(id, pointId, 0, null);
    detail = (await reports.watchReport(id).first)!;
    expect(detail.nodes[1].points.single.gradeOf(0)?.grade, PartGrade.repair);
  });

  test('a report under review is locked', () async {
    final detail = await createFull();
    final id = detail.header.id;
    final pointId = detail.nodes[2].points.single.id;
    expect(
      await reports.setStatus(id, ReportStatus.approved),
      isA<Err<void, ReportFailure>>(),
    );
    await reports.setStatus(id, ReportStatus.review);
    final refused = await reports.addReading(id, pointId, '170');
    expect((refused as Err<void, ReportFailure>).failure, ReportFailure.locked);
    await reports.setStatus(id, ReportStatus.approved);
    final summary = (await reports.watchReports().first).single;
    expect(summary.header.status, ReportStatus.approved);
  });

  test('photo keeps the original and the marked copy', () async {
    final detail = await createFull();
    final source = File(p.join(directory.path, 'shot.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final added = await reports.addPhoto(
      detail.header.id,
      detail.nodes.first.id,
      source.path,
      PhotoInput(
        caption: 'Трещина',
        marks: const [
          PhotoMark(
            tool: MarkTool.arrow,
            color: MarkColor.red,
            x1: 0.1,
            y1: 0.1,
            x2: 0.5,
            y2: 0.5,
          ),
        ],
        annotatedPng: Uint8List.fromList([9, 9]),
      ),
    );
    expect(added, isA<Ok<String, ReportFailure>>());
    final photo = (await reports.watchReport(detail.header.id).first)!
        .nodes
        .first
        .photos
        .single;
    expect(File(photo.originalPath).readAsBytesSync(), [1, 2, 3]);
    expect(File(photo.displayPath).readAsBytesSync(), [9, 9]);
    expect(photo.marks.single.tool, MarkTool.arrow);
  });

  test('print leaves out empty fields, nodes and points; PDF is built', () async {
    var detail = await createFull();
    final id = detail.header.id;
    await reports.addReading(id, detail.nodes[3].points.single.id, '2,4');
    await reports.setRemark(id, detail.nodes.first.id, 'Течь масла');
    detail = (await reports.watchReport(id).first)!;
    final printable = printableReport(detail);
    expect(printable.fields.map((f) => f.label), isNot(contains('Заказчик')));
    expect(printable.nodes.map((n) => n.title), [
      'Приёмочный осмотр',
      'Коробка передач',
    ]);
    expect(printable.nodes.last.points.single.status, ToleranceStatus.outside);
    expect(printable.outsideCount, 1);

    final fonts = PdfFonts(
      regular: ByteData.sublistView(
        File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
      ),
      bold: ByteData.sublistView(
        File('assets/fonts/DejaVuSans-Bold.ttf').readAsBytesSync(),
      ),
    );
    final pdf = await buildReportPdf(
      printable,
      fonts,
      photos: const {},
      printedOn: '08.11.2026',
    );
    expect(ascii.decode(pdf.sublist(0, 4)), '%PDF');
  });
}
