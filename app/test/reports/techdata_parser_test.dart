import 'package:engineer/data/pack/techdata_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('book units come from manual.aggs', () {
    final units = parsePackUnits({
      'agg': 'book',
      'aggs': [
        {'code': 'eng', 'name': 'Двигатель', 'type': 'ДВС'},
        {'code': 'trans', 'name': 'Коробка передач', 'type': 'КПП'},
      ],
    });
    expect(units.map((u) => u.code), ['eng', 'trans']);
    expect(units.last.unitType, 'КПП');
  });

  test('a unit pack is one unit', () {
    final units = parsePackUnits({'agg': 'susp', 'title': 'Подвеска'});
    expect(units.single.code, 'susp');
    expect(units.single.name, 'Подвеска');
  });

  test('specs and torques keep their aggs and bounds', () {
    final specs = parseTechdata({
      'specs': [
        {
          'name': 'Вал',
          'unit': 'мм',
          'nom': 170.0,
          'min': 169.975,
          'max': 170.0,
          'limit': null,
          'page': 91,
          'proc': 'k90',
          'title': 'Выходной вал',
          'code': '10-90',
          'aggs': ['trans'],
        },
        {'name': '', 'unit': 'мм'},
        {'name': 'Без меток', 'unit': 'мм', 'min': 1, 'max': 'x'},
      ],
      'torques': [
        {'nm': '14,7–34', 'kgm': '1,5 - 3,5 кгм', 'op': 'по рисунку'},
      ],
    }, 'eng');
    expect(specs, hasLength(3));
    expect(specs[0].unitCodes, ['trans']);
    expect(specs[0].min, 169.975);
    expect(specs[0].limit, isNull);
    expect(specs[1].unitCodes, ['eng']);
    expect(specs[1].max, isNull);
    expect(specs[2].isTorque, isTrue);
    expect(specs[2].torqueText, contains('14,7–34 Н·м'));
  });
}
