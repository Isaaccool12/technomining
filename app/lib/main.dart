import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:engineer/app.dart';
import 'package:engineer/core/clock.dart';
import 'package:engineer/data/db/app_database.dart';
import 'package:engineer/data/db/connection.dart';
import 'package:engineer/data/file_picker_service.dart';
import 'package:engineer/data/repositories/drift_library_repository.dart';
import 'package:engineer/data/repositories/drift_settings_repository.dart';
import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/settings/settings_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    developer.log(details.exceptionAsString(), stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log('$error', stackTrace: stack);
    return true;
  };
  final support = await getApplicationSupportDirectory();
  final packsRoot = Directory(p.join(support.path, 'packs'));
  await packsRoot.create(recursive: true);
  final database = AppDatabase(openDatabaseFile(support));
  final settings = DriftSettingsRepository(database);
  final initialTheme = await settings.readTheme();
  runApp(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          DriftLibraryRepository(database, const SystemClock(), packsRoot.path),
        ),
        packFilePickerProvider.overrideWithValue(const SystemPackFilePicker()),
        settingsRepositoryProvider.overrideWithValue(settings),
        initialThemeProvider.overrideWithValue(initialTheme),
      ],
      child: const EngineerApp(),
    ),
  );
}
