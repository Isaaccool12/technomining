import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Top level of the library: the machines.
class MachinesScreen extends ConsumerWidget {
  /// Creates the screen.
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen(importProvider, (previous, next) async {
      if (next is! ImportFinished) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ImportSummaryDialog(outcomes: next.outcomes),
      );
      ref.read(importProvider.notifier).acknowledge();
    });
    final isRunning = ref.watch(importProvider) is ImportRunning;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.machinesTitle),
        actions: [
          IconButton(
            iconSize: 32,
            tooltip: l10n.searchAction,
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            iconSize: 32,
            tooltip: l10n.settingsAction,
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: isRunning
          ? null
          : FloatingActionButton.extended(
              onPressed: ref.read(importProvider.notifier).pickAndImport,
              icon: const Icon(Icons.file_open),
              label: Text(l10n.importAction),
            ),
      body: const Column(
        children: [
          _ImportBanner(),
          Expanded(child: _MachineList()),
        ],
      ),
    );
  }
}

class _ImportBanner extends ConsumerWidget {
  const _ImportBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importProvider);
    if (state is! ImportRunning) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.importProgress(state.current, state.total, state.fileName)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.current / state.total),
        ],
      ),
    );
  }
}

class _MachineList extends ConsumerWidget {
  const _MachineList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(machineGroupsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorRetryView(
            onRetry: () => ref.invalidate(machineGroupsProvider),
          ),
          data: (groups) => groups.isEmpty
              ? MessageView(
                  icon: Icons.menu_book,
                  title: l10n.emptyLibraryTitle,
                  hint: l10n.emptyLibraryHint,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: groups.length,
                  itemBuilder: (context, index) =>
                      _MachineTile(group: groups[index]),
                ),
        );
  }
}

class _MachineTile extends StatelessWidget {
  const _MachineTile({required this.group});

  final MachineGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      minTileHeight: 72,
      leading: const Icon(Icons.precision_manufacturing, size: 36),
      title: Text(group.machine.isEmpty ? l10n.noMachine : group.machine),
      subtitle: Text(l10n.manualsCount(group.manuals.length)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(machineLocation(group.routeKey)),
    );
  }
}

class _ImportSummaryDialog extends StatelessWidget {
  const _ImportSummaryDialog({required this.outcomes});

  final List<ImportOutcome> outcomes;

  String _reason(AppLocalizations l10n, ImportFailure failure) =>
      switch (failure) {
        ImportFailure.notZip => l10n.failureNotZip,
        ImportFailure.badFormat => l10n.failureBadFormat,
        ImportFailure.unsupportedVersion => l10n.failureUnsupportedVersion,
        ImportFailure.storage => l10n.failureStorage,
      };

  String _line(AppLocalizations l10n, ImportOutcome outcome) =>
      switch (outcome.result) {
        Ok(:final value) => l10n.importSummaryOk(
          value.title,
          value.procedureCount,
        ),
        Err(:final failure) => l10n.importSummaryError(
          outcome.fileName,
          _reason(l10n, failure),
        ),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.importSummaryTitle),
      content: SingleChildScrollView(
        child: Text(outcomes.map((o) => _line(l10n, o)).join('\n')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
