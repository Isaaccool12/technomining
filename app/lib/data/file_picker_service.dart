import 'package:engineer/features/library/domain/library_repository.dart';
import 'package:file_picker/file_picker.dart';

/// [PackFilePicker] using the system file dialog.
final class SystemPackFilePicker implements PackFilePicker {
  /// Creates the picker.
  const SystemPackFilePicker();

  @override
  Future<List<String>> pickZipFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: true,
    );
    return result?.paths.whereType<String>().toList() ?? const [];
  }

  @override
  Future<void> clearTemporaryFiles() async {
    await FilePicker.platform.clearTemporaryFiles();
  }
}
