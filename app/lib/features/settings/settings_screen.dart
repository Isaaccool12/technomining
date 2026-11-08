import 'package:engineer/features/settings/settings_providers.dart';
import 'package:engineer/features/settings/settings_repository.dart';
import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets the user choose the app theme.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final initial = ref.watch(initialThemeProvider);
    final theme = ref.watch(themeChoiceProvider).value ?? initial;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAction)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.settingsTheme, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<ThemeChoice>(
            segments: [
              ButtonSegment(value: ThemeChoice.auto, label: Text(l10n.themeAuto)),
              ButtonSegment(value: ThemeChoice.light, label: Text(l10n.themeLight)),
              ButtonSegment(value: ThemeChoice.dark, label: Text(l10n.themeDark)),
            ],
            selected: {theme},
            onSelectionChanged: (selection) async {
              await ref.read(settingsRepositoryProvider).saveTheme(selection.first);
            },
          ),
        ],
      ),
    );
  }
}
