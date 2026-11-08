import 'package:engineer/app.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/domain/library_repository.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/report_repository.dart';
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

final class _NoReports implements ReportRepository {
  // Members the screens under test never reach.
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());

  static const Err<Never, ReportFailure> _missing = Err(ReportFailure.missing);

  @override
  String get exportsDirectory => '';

  @override
  Stream<List<ReportSummary>> watchReports() => Stream.value(const []);

  @override
  Stream<ReportDetail?> watchReport(String reportId) => Stream.value(null);

  @override
  Future<List<UnitOption>> unitOptions() async => const [];

  @override
  Future<List<TechSpec>> unitSpecs(String manualId, String unitCode) async =>
      const [];

  @override
  Future<Result<String, ReportFailure>> createReport(NewReport data) async =>
      _missing;

  @override
  Future<Result<String, ReportFailure>> addNode(
    String reportId,
    String title, {
    TechNode? from,
  }) async => _missing;

  @override
  Future<Result<String, ReportFailure>> addPoint(
    String reportId,
    String nodeId,
    String name,
    TechSpec? spec,
  ) async => _missing;

  @override
  Future<Result<void, ReportFailure>> addReading(
    String reportId,
    String pointId,
    String typed,
  ) async => _missing;

  @override
  Future<Result<void, ReportFailure>> setRemark(
    String reportId,
    String nodeId,
    String text,
  ) async => _missing;

  @override
  Future<Result<String, ReportFailure>> addPhoto(
    String reportId,
    String nodeId,
    String sourcePath,
    PhotoInput input,
  ) async => _missing;

  @override
  Future<Result<void, ReportFailure>> updatePhoto(
    String reportId,
    String photoId,
    PhotoInput input,
  ) async => _missing;

  @override
  Future<Result<void, ReportFailure>> removeRecord(
    String reportId,
    String recordId,
  ) async => _missing;

  @override
  Future<Result<void, ReportFailure>> setStatus(
    String reportId,
    ReportStatus status,
  ) async => _missing;
}

Future<void> _pumpApp(WidgetTester tester, List<ManualSummary> manuals) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(_FakeLibrary(manuals)),
        settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        reportRepositoryProvider.overrideWithValue(_NoReports()),
      ],
      child: const EngineerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLibrary(WidgetTester tester) async {
  await tester.tap(find.text('Инструкции').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('app opens on the empty report list', (tester) async {
    await _pumpApp(tester, const []);
    expect(find.text('Отчётов пока нет'), findsOneWidget);
    expect(find.text('Новый отчёт'), findsOneWidget);
  });

  testWidgets('empty library invites to import', (tester) async {
    await _pumpApp(tester, const []);
    await _openLibrary(tester);
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
    await _openLibrary(tester);
    await tester.tap(find.text('HD785-7'));
    await tester.pumpAndSettle();
    expect(find.text('Подвеска'), findsOneWidget);
  });
}
