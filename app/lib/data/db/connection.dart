import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

/// Opens the database file inside [directory].
QueryExecutor openDatabaseFile(Directory directory) {
  return NativeDatabase.createInBackground(
    File(p.join(directory.path, 'engineer.sqlite')),
    setup: (raw) {
      raw
        ..execute('PRAGMA journal_mode = WAL;')
        ..execute('PRAGMA synchronous = FULL;')
        ..execute('PRAGMA busy_timeout = 5000;');
    },
  );
}
