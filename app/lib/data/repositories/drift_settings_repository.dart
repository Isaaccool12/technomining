import 'package:engineer/data/db/app_database.dart';
import 'package:engineer/features/settings/settings_repository.dart';

const String _themeKey = 'theme';

/// [SettingsRepository] over the settings table.
final class DriftSettingsRepository implements SettingsRepository {
  /// Creates the repository.
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<ThemeChoice> readTheme() async {
    final query = _db.select(_db.appSettings)
      ..where((s) => s.key.equals(_themeKey));
    final row = await query.getSingleOrNull();
    return _parse(row?.value);
  }

  @override
  Stream<ThemeChoice> watchTheme() {
    final query = _db.select(_db.appSettings)
      ..where((s) => s.key.equals(_themeKey));
    return query.watchSingleOrNull().map((row) => _parse(row?.value));
  }

  @override
  Future<void> saveTheme(ThemeChoice choice) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: _themeKey, value: choice.name),
        );
  }

  ThemeChoice _parse(String? value) => ThemeChoice.values.firstWhere(
    (choice) => choice.name == value,
    orElse: () => ThemeChoice.auto,
  );
}
