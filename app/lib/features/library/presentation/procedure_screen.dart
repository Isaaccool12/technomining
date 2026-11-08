import 'dart:async';
import 'dart:developer' as developer;

import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shows one procedure offline.
class ProcedureScreen extends ConsumerWidget {
  /// Creates the screen for [procedureId].
  const ProcedureScreen({required this.procedureId, super.key});

  /// Procedure identifier.
  final String procedureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final key = (procedureId: procedureId, isDark: isDark);
    final title = ref.watch(procedureTitleProvider(procedureId)).value ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ref
          .watch(procedurePageProvider(key))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ErrorRetryView(
              onRetry: () => ref.invalidate(procedurePageProvider(key)),
            ),
            data: (result) => _PageBody(result: result),
          ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.result});

  final Result<String, ProcedureViewFailure> result;

  @override
  Widget build(BuildContext context) {
    final page = result;
    return switch (page) {
      Ok(:final value) => _OfflinePage(key: ValueKey(value), filePath: value),
      Err() => MessageView(
        icon: Icons.description,
        title: AppLocalizations.of(context).procedureMissing,
      ),
    };
  }
}

class _OfflinePage extends StatefulWidget {
  const _OfflinePage({required this.filePath, super.key});

  final String filePath;

  @override
  State<_OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<_OfflinePage> {
  final WebViewController _controller = WebViewController();
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoaded) return;
    _isLoaded = true;
    final background = Theme.of(context).scaffoldBackgroundColor;
    unawaited(_load(background).catchError(_logLoadError));
  }

  void _logLoadError(Object error, StackTrace stack) {
    developer.log('$error', stackTrace: stack);
  }

  Future<void> _load(Color background) async {
    await _controller.setJavaScriptMode(JavaScriptMode.disabled);
    await _controller.setBackgroundColor(background);
    await _controller.enableZoom(true);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => request.url.startsWith('file:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    );
    await _controller.loadFile(widget.filePath);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
