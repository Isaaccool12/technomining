import 'dart:async';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/grid.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:engineer/features/reports/presentation/tolerance_badge.dart';
import 'package:flutter/material.dart' hide Tolerance;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int _defaultCylinders = 6;

/// Cylinders and main journals of an engine, set once per report.
class CompositionCard extends ConsumerWidget {
  /// Creates the card.
  const CompositionCard({required this.detail, super.key});

  /// The report.
  final ReportDetail detail;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = detail.composition;
    final cylinders = await _askCount(
      context,
      'Число цилиндров',
      current?.cylinders ?? _defaultCylinders,
    );
    if (cylinders == null || !context.mounted) return;
    final mains = await _askCount(
      context,
      'Число коренных шеек',
      current?.mains ?? cylinders + 1,
    );
    if (mains == null) return;
    final result = await ref
        .read(reportRepositoryProvider)
        .setComposition(detail.header.id, (cylinders: cylinders, mains: mains));
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composition = detail.composition;
    return Card(
      margin: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        minTileHeight: 64,
        leading: const Icon(Icons.settings_input_component),
        title: const Text('Состав агрегата'),
        subtitle: Text(
          composition == null
              ? 'Не задан — нажмите, чтобы указать'
              : 'Цилиндров: ${composition.cylinders} · '
                    'коренных шеек: ${composition.mains}',
        ),
        enabled: detail.header.status.isEditable,
        onTap: () => unawaited(_edit(context, ref)),
      ),
    );
  }
}

Future<int?> _askCount(BuildContext context, String title, int initial) async {
  final controller = TextEditingController(text: '$initial');
  final value = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = int.tryParse(controller.text);
            if (parsed != null && parsed > 0 && parsed <= 40) {
              Navigator.of(context).pop(parsed);
            }
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

typedef _GridChoice = ({GridPreset preset, MeasurementPoint? source});

/// Offers a grid preset and the tolerance to use, then adds the grid.
Future<void> showAddGrid(
  BuildContext context,
  WidgetRef ref,
  String reportId,
  ReportNode node,
  UnitComposition? composition,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showModalBottomSheet<_GridChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GridSheet(
      points: node.points.where((p) => p.grid == null).toList(),
    ),
  );
  if (choice == null || !context.mounted) return;
  final cylinders = composition?.cylinders ?? _defaultCylinders;
  final mains = composition?.mains ?? cylinders + 1;
  final base = choice.preset.spec(cylinders, mains);
  final count = await _askCount(context, 'Число позиций', base.rowCount);
  if (count == null) return;
  final result = await ref
      .read(reportRepositoryProvider)
      .addGrid(
        reportId,
        node.id,
        choice.preset.title,
        GridSpec(
          rowLabel: base.rowLabel,
          rowCount: count,
          positions: base.positions,
          directions: base.directions,
          repairSteps: base.repairSteps,
        ),
        choice.source?.tolerance,
      );
  if (result case Err(:final failure)) {
    messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
  }
}

class _GridSheet extends StatefulWidget {
  const _GridSheet({required this.points});

  final List<MeasurementPoint> points;

  @override
  State<_GridSheet> createState() => _GridSheetState();
}

class _GridSheetState extends State<_GridSheet> {
  GridPreset _preset = GridPreset.liner;
  MeasurementPoint? _source;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Новая сетка', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final preset in GridPreset.values)
                  ChoiceChip(
                    label: Text(preset.title),
                    selected: _preset == preset,
                    onSelected: (_) => setState(() => _preset = preset),
                  ),
              ],
            ),
            if (widget.points.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Допуск взять из замера:'),
              Wrap(
                spacing: 6,
                children: [
                  for (final point in widget.points)
                    ChoiceChip(
                      label: Text(point.name),
                      selected: identical(_source, point),
                      onSelected: (on) =>
                          setState(() => _source = on ? point : null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop<_GridChoice>((preset: _preset, source: _source)),
              child: const Text('Дальше'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Measurement grid: rows of planes × directions with derived values.
class MeasurementGridTile extends ConsumerWidget {
  /// Creates the tile.
  const MeasurementGridTile({
    required this.reportId,
    required this.point,
    required this.isEditable,
    super.key,
  });

  /// Report.
  final String reportId;

  /// Grid.
  final MeasurementPoint point;

  /// Whether values can be changed.
  final bool isEditable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = point.grid!;
    final tolerance = describeTolerance(point.tolerance);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(point.name, style: Theme.of(context).textTheme.titleSmall),
          Text(
            tolerance.isEmpty ? 'Допуск не задан' : 'Допуск: $tolerance',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (var row = 0; row < shape.rowCount; row++)
            _GridRow(
              key: ValueKey('${point.id}-$row'),
              reportId: reportId,
              point: point,
              row: row,
              isEditable: isEditable,
            ),
        ],
      ),
    );
  }
}

class _GridRow extends ConsumerWidget {
  const _GridRow({
    required this.reportId,
    required this.point,
    required this.row,
    required this.isEditable,
    super.key,
  });

  final String reportId;
  final MeasurementPoint point;
  final int row;
  final bool isEditable;

  Future<void> _setGrade(
    BuildContext context,
    WidgetRef ref,
    PartGrade grade,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final same = point.gradeOverrides[row] == grade;
    final result = await ref
        .read(reportRepositoryProvider)
        .setGrade(reportId, point.id, row, same ? null : grade);
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = point.grid!;
    final derived = rowDerived(point.rowValues(row), shape.directions.length);
    final grade = point.gradeOf(row);
    final isAuto = !point.gradeOverrides.containsKey(row);
    final lines = [
      if (derived.ovality != null)
        'Овальность: ${formatDecimal(derived.ovality!)}',
      if (derived.taper != null)
        'Конусность: ${formatDecimal(derived.taper!)}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsetsDirectional.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${shape.rowLabel} ${row + 1}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (var p = 0; p < shape.positions.length; p++)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(width: 72, child: Text(shape.positions[p])),
                    for (var d = 0; d < shape.directions.length; d++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 6),
                          child: _Cell(
                            key: ValueKey(gridCellKey(row, p, d)),
                            reportId: reportId,
                            point: point,
                            cellKey: gridCellKey(row, p, d),
                            label: shape.directions[d],
                            isEditable: isEditable,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (lines.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: Text(lines),
              ),
            if (point.rowHasData(row)) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final option in PartGrade.values)
                    ChoiceChip(
                      label: Text(
                        grade?.grade == option
                            ? gradeLabel(grade!)
                            : option.label,
                      ),
                      selected: grade?.grade == option,
                      onSelected: isEditable
                          ? (_) => unawaited(_setGrade(context, ref, option))
                          : null,
                    ),
                  if (grade != null && isAuto) const Text('авто'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends ConsumerStatefulWidget {
  const _Cell({
    required this.reportId,
    required this.point,
    required this.cellKey,
    required this.label,
    required this.isEditable,
    super.key,
  });

  final String reportId;
  final MeasurementPoint point;
  final String cellKey;
  final String label;
  final bool isEditable;

  @override
  ConsumerState<_Cell> createState() => _CellState();
}

class _CellState extends ConsumerState<_Cell> {
  late final TextEditingController _controller = TextEditingController(
    text: _shown,
  );
  final FocusNode _focus = FocusNode();

  Reading? get _latest {
    final list = widget.point.cellReadings[widget.cellKey];
    return list == null || list.isEmpty ? null : list.first;
  }

  String get _shown {
    final value = _latest?.value;
    return value == null ? '' : formatDecimal(value);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_Cell old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      final shown = _shown;
      if (shown.isNotEmpty && _controller.text != shown) {
        _controller.text = shown;
      }
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) unawaited(_save());
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final canonical = canonicalDecimal(text);
    if (canonical != null && canonical == _latest?.valueText) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(reportRepositoryProvider)
        .addCellReading(widget.reportId, widget.point.id, widget.cellKey, text);
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final number = parseDecimal(value.text);
        final status = number == null
            ? null
            : evaluateReading(number, widget.point.tolerance);
        final style = status == null
            ? null
            : statusStyle(status, Theme.of(context).brightness);
        return TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.isEditable,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-+]')),
          ],
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            suffixIcon: style == null
                ? null
                : Icon(style.icon, color: style.background),
          ),
        );
      },
    );
  }
}

/// Tightening torques of a node's procedure.
class TorqueList extends ConsumerWidget {
  /// Creates the list.
  const TorqueList({required this.unit, required this.procKey, super.key});

  /// Unit of the report.
  final UnitKey unit;

  /// Procedure of the node.
  final String procKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = ref.watch(unitSpecsProvider(unit)).value ?? const <TechSpec>[];
    final torques = specs
        .where((s) => s.isTorque && s.procKey == procKey)
        .toList();
    if (torques.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsetsDirectional.zero,
      leading: const Icon(Icons.build),
      title: Text('Моменты затяжки: ${torques.length}'),
      children: [
        for (final torque in torques)
          ListTile(
            contentPadding: EdgeInsetsDirectional.zero,
            title: Text(torque.name),
            trailing: Text(torque.torqueText),
          ),
      ],
    );
  }
}
