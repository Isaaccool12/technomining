import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/domain/library_models.dart';

/// Single write path and source of truth for imported manuals.
abstract interface class LibraryRepository {
  /// Emits the manuals on every change of the library.
  Stream<List<ManualSummary>> watchManuals();

  /// Loads the sections of a manual in manual order.
  Future<List<ManualSection>> loadSections(String manualId);

  /// Loads the title of a procedure, or null when it does not exist.
  Future<String?> procedureTitle(String procedureId);

  /// Imports the pack at [zipPath], replacing a pack with the same id.
  Future<Result<ImportedPack, ImportFailure>> importPack(String zipPath);

  /// Searches the procedures; an empty list for a blank query.
  Future<List<SearchHit>> search(String query);

  /// Writes a viewable page and returns its file path.
  Future<Result<String, ProcedureViewFailure>> prepareProcedureView(
    String procedureId, {
    required bool isDark,
  });
}

/// Picks pack files from the device.
abstract interface class PackFilePicker {
  /// Returns the chosen ZIP paths; empty when the user cancels.
  Future<List<String>> pickZipFiles();

  /// Removes temporary copies of picked files.
  Future<void> clearTemporaryFiles();
}
