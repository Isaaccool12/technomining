import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:engineer/core/clock.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/data/db/app_database.dart';
import 'package:engineer/data/repositories/drift_library_repository.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _FixedClock implements Clock {
  @override
  int nowUtcMs() => 1794147941000;
}

void _add(Archive archive, String name, List<int> bytes) {
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

/// Mirrors the structure of real packs (`HD785-7_susp_app.zip`).
File _writePack(Directory dir, {String body = 'Снятие подшипников ступицы'}) {
  final index = {
    'format': 'qs-manual-pack',
    'version': 1,
    'manual': {
      'id': 'SRU05900-01-susp',
      'title': 'HD785-7 — Подвеска, рама и кузов',
      'lang': 'ru',
      'doc': 'SRU05900-01',
      'machine': 'HD785-7',
      'unitType': '',
      'agg': 'susp',
      'source': 'komatsu-pdf',
    },
    'sections': [
      {
        'title': '10 Нормативы › Рама',
        'procs': ['k194'],
      },
    ],
    'linked': <String>[],
    'procs': {
      'k194': {
        'code': '10-194',
        'title': 'Подвеска',
        'section': '10 Нормативы › Рама',
        'pages': [194, 195],
      },
    },
  };
  final archive = Archive();
  _add(archive, 'index.json', utf8.encode(jsonEncode(index)));
  _add(archive, 'search.json', utf8.encode(jsonEncode({'k194': 'Подвеска\n$body'})));
  _add(archive, 'techdata.json', utf8.encode('{"torques":[],"specs":[]}'));
  _add(
    archive,
    'proc/k194.html',
    utf8.encode('<div class="kp"><img src="img/ab12.webp"></div>'),
  );
  _add(archive, 'img/ab12.webp', [1, 2, 3]);
  _add(archive, '../evil.html', [1]);
  final file = File(p.join(dir.path, 'pack.zip'));
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late DriftLibraryRepository repository;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('engineer_test');
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLibraryRepository(database, _FixedClock(), directory.path);
  });

  tearDown(() async {
    await database.close();
    directory.deleteSync(recursive: true);
  });

  test('import builds the tree and finds a word in another case', () async {
    final result = await repository.importPack(_writePack(directory).path);
    expect(result, isA<Ok<ImportedPack, ImportFailure>>());

    final groups = groupByMachine(await repository.watchManuals().first);
    expect(groups.single.machine, 'HD785-7');
    expect(groups.single.manuals.single.unitTitle, 'Подвеска, рама и кузов');

    final sections = await repository.loadSections('SRU05900-01-susp');
    expect(sections.single.procedures.single.code, '10-194');

    final hits = await repository.search('подшипник');
    expect(hits.single.title, 'Подвеска');
    expect(hits.single.match, 'подшипников');
  });

  test('re-import replaces the pack and its index entries', () async {
    await repository.importPack(_writePack(directory).path);
    await repository.importPack(_writePack(directory, body: 'Замена втулки').path);

    expect(await repository.search('подшипник'), isEmpty);
    expect(await repository.search('втулка'), hasLength(1));
  });

  test('procedure page is written next to the images', () async {
    await repository.importPack(_writePack(directory).path);
    final page = await repository.prepareProcedureView(
      'SRU05900-01-susp:k194',
      isDark: true,
    );
    final path = (page as Ok<String, ProcedureViewFailure>).value;
    expect(File(p.join(p.dirname(path), 'img', 'ab12.webp')).existsSync(), isTrue);
    expect(File(path).readAsStringSync(), contains('img/ab12.webp'));
  });

  test('entries outside the pack folders are ignored', () async {
    await repository.importPack(_writePack(directory).path);
    expect(File(p.join(p.dirname(directory.path), 'evil.html')).existsSync(), isFalse);
  });

  test('a file that is not a ZIP is reported', () async {
    final file = File(p.join(directory.path, 'bad.zip'))..writeAsStringSync('no');
    final result = await repository.importPack(file.path);
    expect(result, isA<Err<ImportedPack, ImportFailure>>());
  });

  test('import is written to the operation journal with an HLC', () async {
    await repository.importPack(_writePack(directory).path);
    final operations = await database.select(database.operationLog).get();
    expect(operations.single.operation, 'import');
    expect(operations.single.hlc, startsWith('001794147941000-'));
  });
}
