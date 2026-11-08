import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';

/// Route of a machine.
String machineLocation(String key) => '/machine/${Uri.encodeComponent(key)}';

/// Route of a manual.
String manualLocation(String id) => '/manual/${Uri.encodeComponent(id)}';

/// Route of a procedure.
String procedureLocation(String id) => '/procedure/${Uri.encodeComponent(id)}';

/// Centered icon with explanatory text.
class MessageView extends StatelessWidget {
  /// Creates the view.
  const MessageView({
    required this.icon,
    required this.title,
    this.hint,
    super.key,
  });

  /// Decorative icon.
  final IconData icon;

  /// Main message.
  final String title;

  /// Optional details.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = hint;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 72)),
            const SizedBox(height: 16),
            Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(details, style: textTheme.bodyLarge, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error message with a retry action.
class ErrorRetryView extends StatelessWidget {
  /// Creates the view.
  const ErrorRetryView({required this.onRetry, super.key});

  /// Called when the user asks to retry.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageView(icon: Icons.error_outline, title: l10n.loadError),
          FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
