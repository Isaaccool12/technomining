import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/presentation/machine_screen.dart';
import 'package:engineer/features/library/presentation/machines_screen.dart';
import 'package:engineer/features/library/presentation/manual_screen.dart';
import 'package:engineer/features/library/presentation/procedure_screen.dart';
import 'package:engineer/features/search/search_screen.dart';
import 'package:engineer/features/settings/settings_providers.dart';
import 'package:engineer/features/settings/settings_repository.dart';
import 'package:engineer/features/settings/settings_screen.dart';
import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Builds the app router.
GoRouter createRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const MachinesScreen()),
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/machine/:key',
      builder: (_, state) =>
          MachineScreen(machineKey: state.pathParameters['key'] ?? '-'),
    ),
    GoRoute(
      path: '/manual/:id',
      builder: (_, state) => _ManualRoute(state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/procedure/:id',
      builder: (_, state) =>
          ProcedureScreen(procedureId: state.pathParameters['id'] ?? ''),
    ),
  ],
);

class _ManualRoute extends ConsumerWidget {
  const _ManualRoute(this.manualId);

  final String manualId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(machineGroupsProvider).value ?? const <MachineGroup>[];
    final manuals = groups.expand((g) => g.manuals).where((m) => m.id == manualId);
    final title = manuals.isEmpty ? '' : manuals.first.unitTitle;
    return ManualScreen(manualId: manualId, title: title);
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final base = ThemeData(
    colorSchemeSeed: const Color(0xFFB7791F),
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    textTheme: Typography.englishLike2021
        .merge(base.textTheme)
        .apply(fontSizeFactor: 1.12),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
  );
}

/// Root widget of the app.
class EngineerApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const EngineerApp({super.key});

  @override
  ConsumerState<EngineerApp> createState() => _EngineerAppState();
}

class _EngineerAppState extends ConsumerState<EngineerApp> {
  final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  ThemeMode _mode(ThemeChoice choice) => switch (choice) {
    ThemeChoice.auto => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };

  @override
  Widget build(BuildContext context) {
    final initial = ref.watch(initialThemeProvider);
    final choice = ref.watch(themeChoiceProvider).value ?? initial;
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _mode(choice),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ru'),
      routerConfig: _router,
    );
  }
}
