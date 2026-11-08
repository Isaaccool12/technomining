import 'package:engineer/features/settings/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings repository, provided at the composition root.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('Provided in bootstrap'),
);

/// Theme stored before the first frame, so the app starts in the right theme.
final initialThemeProvider = Provider<ThemeChoice>((ref) => ThemeChoice.auto);

/// The current theme.
final themeChoiceProvider = StreamProvider<ThemeChoice>(
  (ref) => ref.watch(settingsRepositoryProvider).watchTheme(),
);
