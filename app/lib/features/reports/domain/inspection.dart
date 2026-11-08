/// Finding of the acceptance inspection (form Komatsu CSTS13-007).
enum InspectionCondition {
  /// Oil or coolant leak.
  leak('leak', 'Утечка масла/ОЖ'),

  /// Loose bolt or nut.
  loose('loose', 'Ослаблен болт (гайка)'),

  /// Deformation.
  deformation('deformation', 'Деформация'),

  /// Crack.
  crack('crack', 'Трещина'),

  /// Damage.
  damage('damage', 'Повреждение'),

  /// Seizure.
  seizure('seizure', 'Заклинивание'),

  /// Deterioration.
  worn('worn', 'Обветшание'),

  /// Missing parts.
  missing('missing', 'Недостающие детали');

  const InspectionCondition(this.code, this.label);

  /// Stored code.
  final String code;

  /// Russian label.
  final String label;
}

/// Action the finding requires.
enum InspectionAction {
  /// Check.
  check('check', 'Проверка'),

  /// Adjust.
  adjust('adjust', 'Регулировка'),

  /// Replace.
  replace('replace', 'Замена');

  const InspectionAction(this.code, this.label);

  /// Stored code.
  final String code;

  /// Russian label.
  final String label;
}

/// One line of the inspection sheet.
final class InspectionItem {
  /// Creates a line.
  const InspectionItem({
    required this.id,
    required this.name,
    required this.isStandard,
    this.isClean = false,
    this.conditions = const {},
    this.actions = const {},
    this.note = '',
  });

  /// Record id.
  final String id;

  /// Inspected assembly.
  final String name;

  /// Whether the line comes from the typical list and cannot be removed.
  final bool isStandard;

  /// Marked "Без замечаний".
  final bool isClean;

  /// Findings.
  final Set<InspectionCondition> conditions;

  /// Required actions.
  final Set<InspectionAction> actions;

  /// Note.
  final String note;

  /// Whether the engineer has looked at this line.
  bool get isInspected =>
      isClean ||
      conditions.isNotEmpty ||
      actions.isNotEmpty ||
      note.trim().isNotEmpty;

  /// One-line result; empty when not inspected.
  String get summary {
    if (isClean) return 'Без замечаний';
    return [
      ...conditions.map((c) => c.label),
      ...actions.map((a) => a.label),
      if (note.trim().isNotEmpty) note.trim(),
    ].join(', ');
  }
}

/// Node titles that carry the inspection sheet.
const Set<String> inspectionNodeTitles = {
  'Приёмочный осмотр',
  'Прибытие: внешний осмотр',
};

/// Typical assemblies to inspect for a unit type; matched by words in the
/// type because packs name types freely (`ДВС`, `КПП`, `АКПП`, …).
List<String> inspectionListFor(String unitType) {
  final type = unitType.toLowerCase();
  if (type.contains('двс') || type.contains('двигат')) return _engine;
  if (type.contains('гидротрансформ')) return _converter;
  if (type.contains('кпп') || type.contains('коробк')) return _gearbox;
  if (type.contains('мост')) return _axle;
  if (type.contains('раздат')) return _transferCase;
  if (type.contains('насос')) return _pump;
  if (type.contains('редуктор')) return _reducer;
  return _other;
}

const List<String> _engine = [
  'Блок цилиндров',
  'Головка блока цилиндров',
  'Крышка клапанного механизма',
  'Масляный поддон',
  'Масляный насос',
  'Масляный радиатор и фильтры',
  'Топливный насос',
  'Форсунки и топливопроводы',
  'Турбокомпрессор',
  'Впускной коллектор',
  'Выпускной коллектор',
  'Водяной насос',
  'Термостат и патрубки',
  'Маховик и картер маховика',
  'Демпфер коленчатого вала',
  'Стартер',
  'Генератор',
  'Навесное оборудование и кронштейны',
];

const List<String> _gearbox = [
  'Корпус',
  'Входной вал',
  'Выходной вал',
  'Клапаны управления',
  'Масляный насос',
  'Масляный фильтр и магниты',
  'Поддон',
  'Датчики и проводка',
  'Трубопроводы',
];

const List<String> _converter = [
  'Корпус',
  'Входной фланец',
  'Выходной вал',
  'Муфта блокировки',
  'Масляные каналы и трубопроводы',
  'Датчики',
];

const List<String> _axle = [
  'Картер моста',
  'Главная передача',
  'Дифференциал',
  'Полуоси',
  'Бортовые редукторы',
  'Ступицы',
  'Тормозные механизмы',
  'Сапун и заливные пробки',
];

const List<String> _transferCase = [
  'Корпус',
  'Входной фланец',
  'Выходные фланцы',
  'Механизм переключения',
  'Сапун и пробки',
];

const List<String> _pump = [
  'Корпус',
  'Приводной вал и уплотнение',
  'Регулятор',
  'Штуцеры и фланцы',
];

const List<String> _reducer = [
  'Корпус',
  'Входной вал',
  'Выходной вал',
  'Сапун и пробки',
];

const List<String> _other = ['Корпус', 'Крепление', 'Уплотнения', 'Соединения'];
