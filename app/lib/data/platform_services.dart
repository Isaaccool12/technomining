import 'package:engineer/features/reports/domain/report_services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Longest side of a stored photo, pixels.
const double maxPhotoSide = 2048;

/// [PhotoSource] over the system camera and gallery.
final class SystemPhotoSource implements PhotoSource {
  /// Creates the source.
  const SystemPhotoSource();

  @override
  Future<String?> pick({required bool fromCamera}) async {
    final file = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxPhotoSide,
      maxHeight: maxPhotoSide,
      imageQuality: 85,
    );
    return file?.path;
  }
}

/// [FileSharer] over the system share sheet.
final class SystemFileSharer implements FileSharer {
  /// Creates the sharer.
  const SystemFileSharer();

  @override
  Future<void> share(String path, String mimeType) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: mimeType)]),
    );
  }
}
