import 'package:engineer/features/reports/domain/report_models.dart';

/// Which nodes a new report gets.
final class ReportTemplate {
  /// Creates a template.
  const ReportTemplate({
    required this.leadingNodes,
    required this.trailingNodes,
    required this.techNodes,
  });

  /// General nodes before the technical-data nodes.
  final List<String> leadingNodes;

  /// General nodes after them.
  final List<String> trailingNodes;

  /// Which technical-data nodes are added.
  final TechNodeChoice techNodes;
}

/// How the technical-data nodes are chosen.
enum TechNodeChoice {
  /// Every procedure of the unit that has tolerances.
  all,

  /// Only the procedures picked when the report is created.
  selected,

  /// None; the engineer adds nodes in the report.
  none,
}

/// Template of a report [type].
ReportTemplate templateFor(ReportType type) => switch (type) {
  ReportType.full => const ReportTemplate(
    leadingNodes: ['Приёмочный осмотр', 'Разборка и неисправности'],
    trailingNodes: ['Сборка и испытания'],
    techNodes: TechNodeChoice.all,
  ),
  ReportType.partial => const ReportTemplate(
    leadingNodes: ['Приёмочный осмотр', 'Разборка и неисправности'],
    trailingNodes: ['Сборка и испытания'],
    techNodes: TechNodeChoice.selected,
  ),
  ReportType.field => const ReportTemplate(
    leadingNodes: ['Осмотр на месте', 'Выявленные неисправности'],
    trailingNodes: ['Выполненные работы', 'Рекомендации'],
    techNodes: TechNodeChoice.none,
  ),
  ReportType.arrival => const ReportTemplate(
    leadingNodes: ['Прибытие: внешний осмотр', 'Комплектность'],
    trailingNodes: ['Отправка'],
    techNodes: TechNodeChoice.none,
  ),
};

/// Technical-data nodes a new report gets.
List<TechNode> techNodesFor(
  ReportTemplate template,
  List<TechNode> available,
  Set<String> selected,
) => switch (template.techNodes) {
  TechNodeChoice.all => available,
  TechNodeChoice.selected =>
    available.where((n) => selected.contains(n.procKey)).toList(),
  TechNodeChoice.none => const [],
};

/// Groups [specs] by procedure in source order; torques are left out.
List<TechNode> groupTechNodes(List<TechSpec> specs) {
  final groups = <String, List<TechSpec>>{};
  for (final spec in specs) {
    if (spec.isTorque) continue;
    groups.putIfAbsent(spec.procKey, () => []).add(spec);
  }
  return [
    for (final entry in groups.entries)
      TechNode(
        procKey: entry.key,
        title: entry.value.first.procTitle,
        code: entry.value.first.procCode,
        specs: entry.value,
      ),
  ];
}
