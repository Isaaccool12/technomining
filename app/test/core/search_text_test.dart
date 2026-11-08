import 'package:engineer/core/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('different case endings reduce to one stem', () {
    expect(stemWord('подшипника'), stemWord('подшипники'));
    expect(stemWord('Коренными'), stemWord('коренных'));
  });

  test('ё is searched as е', () {
    expect(stemWord('ёмкость'), stemWord('емкость'));
  });

  test('blank query has no match expression', () {
    expect(buildMatchExpression('  --  '), isNull);
  });

  test('query words become required prefixes', () {
    expect(buildMatchExpression('6D170 клапан'), '"6d170"* "клапан"*');
  });

  test('snippet keeps the word as written', () {
    final snippet = buildSnippet('Снять Подшипники вала', ['подшипник']);
    expect(snippet.match, 'Подшипники');
    expect(snippet.before, 'Снять ');
  });
}
