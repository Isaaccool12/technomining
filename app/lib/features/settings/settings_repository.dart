/// Theme choices of the app.
enum ThemeChoice {
  /// Follow the device setting.
  auto,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// Persisted user settings.
abstract interface class SettingsRepository {
  /// Reads the stored theme once.
  Future<ThemeChoice> readTheme();

  /// Emits the theme on every change.
  Stream<ThemeChoice> watchTheme();

  /// Stores the theme.
  Future<void> saveTheme(ThemeChoice choice);
}
