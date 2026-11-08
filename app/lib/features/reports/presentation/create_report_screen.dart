import 'dart:async';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/report_templates.dart';
import 'package:engineer/features/reports/presentation/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Form of a new report.
class CreateReportScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateReportScreen({super.key});

  @override
  ConsumerState<CreateReportScreen> createState() => _CreateReportState();
}

class _CreateReportState extends ConsumerState<CreateReportScreen> {
  final TextEditingController _machine = TextEditingController();
  final TextEditingController _serial = TextEditingController();
  final TextEditingController _customer = TextEditingController();
  ReportType _type = ReportType.full;
  UnitOption? _unit;
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void dispose() {
    _machine.dispose();
    _serial.dispose();
    _customer.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final result = await ref
        .read(reportRepositoryProvider)
        .createReport(
          NewReport(
            type: _type,
            machine: _machine.text,
            unit: _unit,
            serialNo: _serial.text,
            customer: _customer.text,
            selectedProcKeys: _selected,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Ok(:final value):
        context.pushReplacement(reportLocation(value));
      case Err(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  String _unitLabel(UnitOption u) =>
      '${u.machine.isEmpty ? '' : '${u.machine} · '}${u.name}'
      '${u.specCount > 0 ? ' (допусков: ${u.specCount})' : ''}';

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitOptionsProvider).value ?? const <UnitOption>[];
    final unit = _unit;
    final needsSelection =
        templateFor(_type).techNodes == TechNodeChoice.selected &&
        unit != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Новый отчёт')),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: [
          Text('Вид работ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in ReportType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<UnitOption?>(
            initialValue: unit,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Агрегат из инструкций (допуски)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<UnitOption?>(
                child: Text('Без техданных'),
              ),
              for (final u in units)
                DropdownMenuItem<UnitOption?>(
                  value: u,
                  child: Text(_unitLabel(u), overflow: TextOverflow.fade),
                ),
            ],
            onChanged: (value) => setState(() {
              _unit = value;
              _selected.clear();
              if (value != null && _machine.text.trim().isEmpty) {
                _machine.text = value.machine;
              }
            }),
          ),
          const SizedBox(height: 16),
          _field(_machine, 'Машина (модель, гаражный №)'),
          _field(_serial, 'Заводской номер агрегата'),
          _field(_customer, 'Заказчик'),
          if (needsSelection) _NodeChooser(unit: unit, selected: _selected),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _saving ? null : () => unawaited(_create()),
            icon: const Icon(Icons.check),
            label: const Text('Создать отчёт'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: 16),
    child: TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _NodeChooser extends ConsumerStatefulWidget {
  const _NodeChooser({required this.unit, required this.selected});

  final UnitOption unit;
  final Set<String> selected;

  @override
  ConsumerState<_NodeChooser> createState() => _NodeChooserState();
}

class _NodeChooserState extends ConsumerState<_NodeChooser> {
  @override
  Widget build(BuildContext context) {
    final key = (manualId: widget.unit.manualId, unitCode: widget.unit.code);
    final specs = ref.watch(unitSpecsProvider(key)).value ?? const <TechSpec>[];
    final nodes = groupTechNodes(specs);
    if (nodes.isEmpty) {
      return const Text('У агрегата нет допусков — узлы добавляются в отчёте.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Узлы частичной разборки',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final node in nodes)
          CheckboxListTile(
            value: widget.selected.contains(node.procKey),
            title: Text(node.title),
            subtitle: Text('${node.code} · допусков: ${node.specs.length}'),
            onChanged: (checked) => setState(() {
              if (checked ?? false) {
                widget.selected.add(node.procKey);
              } else {
                widget.selected.remove(node.procKey);
              }
            }),
          ),
      ],
    );
  }
}
