final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _cyrillicWord = RegExp(r'^[а-я]+$');

const List<String> _endings = [
  'иями', 'ями', 'ами', 'иях', 'ого', 'его', 'ому', 'ему', 'ыми', 'ими', //
  'ать', 'ять', 'ить', 'ешь', 'ишь', 'ает', 'яет', 'ует', 'ают', 'яют', //
  'уют', 'ах', 'ях', 'ов', 'ев', 'ей', 'ой', 'ий', 'ый', 'ая', 'яя', 'ое', //
  'ее', 'ые', 'ие', 'ых', 'их', 'ую', 'юю', 'ом', 'ем', 'ам', 'ям', 'ию', //
  'ия', 'ии', 'а', 'я', 'о', 'е', 'ы', 'и', 'у', 'ю', 'ь', 'й',
];

const int _minStemLength = 3;

/// Reduces one word to the form stored in the search index.
String stemWord(String word) {
  final lower = word.toLowerCase().replaceAll('ё', 'е');
  if (!_cyrillicWord.hasMatch(lower)) return lower;
  for (final ending in _endings) {
    final isCut = lower.length - ending.length >= _minStemLength;
    if (isCut && lower.endsWith(ending)) {
      return lower.substring(0, lower.length - ending.length);
    }
  }
  return lower;
}

/// Converts [text] to space-separated stems for the FTS5 index.
String normalizeForIndex(String text) =>
    _wordPattern.allMatches(text).map((m) => stemWord(m[0] ?? '')).join(' ');

/// Stems of the words of a user [query].
List<String> queryStems(String query) => _wordPattern
    .allMatches(query)
    .map((m) => stemWord(m[0] ?? ''))
    .where((stem) => stem.isNotEmpty)
    .toList();

/// Builds an FTS5 MATCH expression: every stem as a prefix, all required.
///
/// Returns null when [query] has no searchable words.
String? buildMatchExpression(String query) {
  final stems = queryStems(query);
  if (stems.isEmpty) return null;
  return stems.map((stem) => '"$stem"*').join(' ');
}

/// A fragment of text with the matched word set apart.
final class SearchSnippet {
  /// Creates a snippet from its three parts.
  const SearchSnippet({
    required this.before,
    required this.match,
    required this.after,
  });

  /// Text before the matched word.
  final String before;

  /// The matched word as written in the source.
  final String match;

  /// Text after the matched word.
  final String after;
}

/// Finds the first word of [text] matching [stems] and cuts a fragment around.
SearchSnippet buildSnippet(String text, List<String> stems, {int radius = 60}) {
  for (final found in _wordPattern.allMatches(text)) {
    final stem = stemWord(found[0] ?? '');
    if (!stems.any(stem.startsWith)) continue;
    final start = found.start - radius < 0 ? 0 : found.start - radius;
    final end = found.end + radius > text.length
        ? text.length
        : found.end + radius;
    return SearchSnippet(
      before: _clean(text.substring(start, found.start), cut: start > 0),
      match: found[0] ?? '',
      after: text.substring(found.end, end).replaceAll('\n', ' '),
    );
  }
  final end = text.length < radius * 2 ? text.length : radius * 2;
  return SearchSnippet(
    before: '',
    match: '',
    after: text.substring(0, end).replaceAll('\n', ' '),
  );
}

String _clean(String part, {required bool cut}) {
  final flat = part.replaceAll('\n', ' ');
  return cut ? '…$flat' : flat;
}
