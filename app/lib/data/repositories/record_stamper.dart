import 'package:drift/drift.dart';
import 'package:engineer/core/clock.dart';
import 'package:engineer/core/hlc.dart';
import 'package:engineer/data/db/app_database.dart';
import 'package:uuid/uuid.dart';

const String _deviceIdKey = 'device_id';
const String _hlcKey = 'hlc_last';

/// Author, HLC stamp and time shared by the rows of one change.
final class RecordStamp {
  /// Creates a stamp.
  const RecordStamp({
    required this.authorId,
    required this.hlc,
    required this.nowUtcMs,
  });

  /// Author of the change.
  final String authorId;

  /// Text form of the hybrid clock stamp.
  final String hlc;

  /// Time of the change, UTC milliseconds.
  final int nowUtcMs;
}

/// Issues change stamps and writes the operation journal.
final class RecordStamper {
  /// Creates the stamper.
  RecordStamper(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Advances the persisted clock; call inside the change's transaction.
  Future<RecordStamp> nextStamp() async {
    final node = await _deviceId();
    final last = Hlc.tryParse(await _read(_hlcKey) ?? '') ?? Hlc.zero(node);
    final now = _clock.nowUtcMs();
    final next = last.tick(now).toString();
    await _write(_hlcKey, next);
    return RecordStamp(authorId: 'device:$node', hlc: next, nowUtcMs: now);
  }

  /// Appends one journal entry stamped by [stamp].
  Future<void> logOperation(
    RecordStamp stamp, {
    required String entityType,
    required String entityId,
    required String operation,
    String? field,
    String? oldValue,
    String? newValue,
  }) async {
    await _db
        .into(_db.operationLog)
        .insert(
          OperationLogCompanion.insert(
            id: const Uuid().v4(),
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            field: Value(field),
            oldValue: Value(oldValue),
            newValue: Value(newValue),
            authorId: stamp.authorId,
            hlc: stamp.hlc,
            createdAtUtcMs: stamp.nowUtcMs,
          ),
        );
  }

  Future<String> _deviceId() async {
    final stored = await _read(_deviceIdKey);
    if (stored != null) return stored;
    final created = const Uuid().v4();
    await _write(_deviceIdKey, created);
    return created;
  }

  Future<String?> _read(String key) async {
    final query = _db.select(_db.appSettings)
      ..where((s) => s.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }
}
