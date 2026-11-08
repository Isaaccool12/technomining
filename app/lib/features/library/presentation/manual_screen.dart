import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Procedures of one manual, grouped by section.
class ManualScreen extends ConsumerWidget {
  /// Creates the screen for [manualId].
  const ManualScreen({required this.manualId, required this.title, super.key});

  /// Manual identifier.
  final String manualId;

  /// Title shown in the app bar.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ref
          .watch(manualSectionsProvider(manualId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ErrorRetryView(
              onRetry: () => ref.invalidate(manualSectionsProvider(manualId)),
            ),
            data: (sections) => ListView.builder(
              itemCount: sections.length,
              itemBuilder: (context, index) =>
                  _SectionTile(section: sections[index]),
            ),
          ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section});

  final ManualSection section;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      minTileHeight: 72,
      title: Text(section.title),
      children: [
        for (final procedure in section.procedures)
          ListTile(
            minTileHeight: 64,
            title: Text(procedure.title),
            subtitle: Text(procedure.code),
            onTap: () => context.push(procedureLocation(procedure.id)),
          ),
      ],
    );
  }
}
