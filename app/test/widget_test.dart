import 'package:engineer/app.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/domain/library_repository.dart';
import 'package:engineer/features/settings/settings_providers.dart';
import 'package:engineer/features/settings/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeLibrary implements LibraryRepository {
  _FakeLibrary(this.manuals);

  final List<ManualSummary> manuals;

  @override
  Stream<List<ManualSummary>> watchManuals() => Stream.value(manuals);

  @override
  Future<Result<ImportedPack, ImportFailure>> importPack(String zipPath) async =>
      const Err(ImportFailure.notZip);

  @override
  Future<List<ManualSection>> loadSections(String manualId) async => const [];

  @override
  Future<Result<String, ProcedureViewFailure>> prepareProcedureView(
    String procedureId, {
    required bool isDark,
  }) async => const Err(ProcedureViewFailure.missing);

  @override
  Future<String?> procedureTitle(String procedureId) async => null;

  @override
  Future<List<SearchHit>> search(String query) async => const [];
}

final class _FakeSettings implements SettingsRepository {
  @override
  Future<ThemeChoice> readTheme() async => ThemeChoice.auto;

  @override
  Future<void> saveTheme(ThemeChoice choice) async {}

  @override
  Stream<ThemeChoice> watchTheme() => Stream.value(ThemeChoice.auto);
}

Future<void> _pumpApp(WidgetTester tester, List<ManualSummary> manuals) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(_FakeLibrary(manuals)),
        settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      ],
      child: const EngineerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty library invites to import', (tester) async {
    await _pumpApp(tester, const []);
    expect(find.text('Инструкций пока нет'), findsOneWidget);
    expect(find.text('Импорт пакетов'), findsOneWidget);
  });

  testWidgets('tree goes from machine to unit', (tester) async {
    await _pumpApp(tester, const [
      ManualSummary(
        id: 'm1',
        title: 'HD785-7 — Подвеска',
        machine: 'HD785-7',
        language: 'ru',
        documentCode: 'SRU05900-01',
        procedureCount: 38,
      ),
    ]);
    await tester.tap(find.text('HD785-7'));
    await tester.pumpAndSettle();
    expect(find.text('Подвеска'), findsOneWidget);
  });
}
