import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Units (manuals) of one machine.
class MachineScreen extends ConsumerWidget {
  /// Creates the screen for the machine with [machineKey].
  const MachineScreen({required this.machineKey, super.key});

  /// Route key of the machine.
  final String machineKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(machineKey == '-' ? l10n.noMachine : machineKey)),
      body: ref
          .watch(machineGroupsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ErrorRetryView(
              onRetry: () => ref.invalidate(machineGroupsProvider),
            ),
            data: (groups) {
              final manuals = groups
                  .where((g) => g.routeKey == machineKey)
                  .expand((g) => g.manuals)
                  .toList();
              return ListView.builder(
                itemCount: manuals.length,
                itemBuilder: (context, index) =>
                    _ManualTile(manual: manuals[index]),
              );
            },
          ),
    );
  }
}

class _ManualTile extends StatelessWidget {
  const _ManualTile({required this.manual});

  final ManualSummary manual;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details =
        '${manual.documentCode} · ${manual.language.toUpperCase()} · '
        '${l10n.proceduresCount(manual.procedureCount)}';
    return ListTile(
      minTileHeight: 72,
      title: Text(manual.unitTitle),
      subtitle: Text(details),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(manualLocation(manual.id)),
    );
  }
}
