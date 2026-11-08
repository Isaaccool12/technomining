import 'dart:async';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/domain/library_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Library repository, provided at the composition root.
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => throw UnimplementedError('Provided in bootstrap'),
);

/// Pack file picker, provided at the composition root.
final packFilePickerProvider = Provider<PackFilePicker>(
  (ref) => throw UnimplementedError('Provided in bootstrap'),
);

/// Library grouped by machine.
final machineGroupsProvider = StreamProvider.autoDispose<List<MachineGroup>>(
  (ref) =>
      ref.watch(libraryRepositoryProvider).watchManuals().map(groupByMachine),
);

/// Sections of one manual.
final manualSectionsProvider = FutureProvider.autoDispose
    .family<List<ManualSection>, String>(
      (ref, manualId) =>
          ref.watch(libraryRepositoryProvider).loadSections(manualId),
    );

/// Title of one procedure.
final procedureTitleProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, id) => ref.watch(libraryRepositoryProvider).procedureTitle(id),
    );

/// Identifies a procedure page in one theme.
typedef ProcedurePageKey = ({String procedureId, bool isDark});

/// Prepared offline page of a procedure.
final procedurePageProvider = FutureProvider.autoDispose
    .family<Result<String, ProcedureViewFailure>, ProcedurePageKey>(
      (ref, key) => ref
          .watch(libraryRepositoryProvider)
          .prepareProcedureView(key.procedureId, isDark: key.isDark),
    );

/// Outcome of one file in an import batch.
final class ImportOutcome {
  /// Creates an outcome.
  const ImportOutcome({required this.fileName, required this.result});

  /// Name of the imported file.
  final String fileName;

  /// Import result.
  final Result<ImportedPack, ImportFailure> result;
}

/// State of the pack import.
sealed class ImportState {
  /// Base constructor.
  const ImportState();
}

/// No import is running.
final class ImportIdle extends ImportState {
  /// Creates the state.
  const ImportIdle();
}

/// An import batch is running.
final class ImportRunning extends ImportState {
  /// Creates the state.
  const ImportRunning({
    required this.current,
    required this.total,
    required this.fileName,
  });

  /// One-based position of the current pack.
  final int current;

  /// Number of packs in the batch.
  final int total;

  /// Name of the current file.
  final String fileName;
}

/// An import batch has finished.
final class ImportFinished extends ImportState {
  /// Creates the state.
  const ImportFinished(this.outcomes);

  /// Outcome of each file.
  final List<ImportOutcome> outcomes;
}

/// Runs import batches.
class ImportNotifier extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportIdle();

  /// Asks for files and imports them one by one.
  Future<void> pickAndImport() async {
    if (state is ImportRunning) return;
    final picker = ref.read(packFilePickerProvider);
    final paths = await picker.pickZipFiles();
    if (paths.isEmpty) return;
    final outcomes = await importFiles(paths);
    await picker.clearTemporaryFiles();
    state = ImportFinished(outcomes);
  }

  /// Imports [paths] in order, reporting progress through the state.
  Future<List<ImportOutcome>> importFiles(List<String> paths) async {
    final repository = ref.read(libraryRepositoryProvider);
    final outcomes = <ImportOutcome>[];
    for (var i = 0; i < paths.length; i++) {
      final fileName = paths[i].split(RegExp(r'[/\\]')).last;
      state = ImportRunning(
        current: i + 1,
        total: paths.length,
        fileName: fileName,
      );
      final result = await repository.importPack(paths[i]);
      outcomes.add(ImportOutcome(fileName: fileName, result: result));
    }
    return outcomes;
  }

  /// Returns to the idle state after the summary was shown.
  void acknowledge() => state = const ImportIdle();
}

/// Provider of the import state.
final importProvider = NotifierProvider<ImportNotifier, ImportState>(
  ImportNotifier.new,
);
