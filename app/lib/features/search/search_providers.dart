import 'dart:async';

import 'package:engineer/features/library/application/library_providers.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Duration _debounce = Duration(milliseconds: 300);

/// Holds the applied search query, delaying updates while the user types.
class SearchQueryNotifier extends Notifier<String> {
  Timer? _timer;

  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    return '';
  }

  /// Schedules [query] to be applied after a typing pause.
  void update(String query) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => state = query);
  }
}

/// Provider of the applied search query.
final searchQueryProvider =
    NotifierProvider.autoDispose<SearchQueryNotifier, String>(
      SearchQueryNotifier.new,
    );

/// Results for the applied query.
final searchResultsProvider = FutureProvider.autoDispose<List<SearchHit>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(libraryRepositoryProvider).search(query);
});
