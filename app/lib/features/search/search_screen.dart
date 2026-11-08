import 'package:engineer/features/library/domain/library_models.dart';
import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:engineer/features/search/search_providers.dart';
import 'package:engineer/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-text search across all imported procedures.
class SearchScreen extends ConsumerWidget {
  /// Creates the screen.
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          style: const TextStyle(fontSize: 20),
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            border: InputBorder.none,
          ),
          onChanged: ref.read(searchQueryProvider.notifier).update,
        ),
      ),
      body: const _SearchBody(),
    );
  }
}

class _SearchBody extends ConsumerWidget {
  const _SearchBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (ref.watch(searchQueryProvider).trim().isEmpty) {
      return MessageView(icon: Icons.search, title: l10n.searchPrompt);
    }
    return ref
        .watch(searchResultsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorRetryView(
            onRetry: () => ref.invalidate(searchResultsProvider),
          ),
          data: (hits) => hits.isEmpty
              ? MessageView(icon: Icons.search_off, title: l10n.searchEmpty)
              : ListView.builder(
                  itemCount: hits.length,
                  itemBuilder: (context, index) => _HitTile(hit: hits[index]),
                ),
        );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(hit.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hit.location),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: hit.before),
                TextSpan(
                  text: hit.match,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: hit.after),
              ],
            ),
          ),
        ],
      ),
      onTap: () => context.push(procedureLocation(hit.procedureId)),
    );
  }
}
