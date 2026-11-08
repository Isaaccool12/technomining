// Single-method seams for platform services, injected at the composition
// root so that screens stay testable.
// ignore_for_file: one_member_abstracts

/// Takes a photo with the camera or picks one from the gallery.
abstract interface class PhotoSource {
  /// Path of the taken or picked photo; null when the user cancelled.
  Future<String?> pick({required bool fromCamera});
}

/// Hands a file to the system share sheet.
abstract interface class FileSharer {
  /// Shares the file at [path] with the [mimeType].
  Future<void> share(String path, String mimeType);
}
