import 'dart:async';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/inspection.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _viewKey = 'inspection_view';

/// Asks whether to build the report despite [missed] lines.
Future<bool> confirmUninspected(
  BuildContext context,
  List<String> missed,
) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Не осмотрено: ${missed.length}'),
      content: SingleChildScrollView(
        child: Text(
          '${missed.join('\n')}\n\nВ PDF эти узлы не попадут.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Вернуться'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Сформировать'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

enum _View { list, table, cards }

InspectionItem _copy(
  InspectionItem item, {
  bool? isClean,
  Set<InspectionCondition>? conditions,
  Set<InspectionAction>? actions,
  String? note,
}) => InspectionItem(
  id: item.id,
  name: item.name,
  isStandard: item.isStandard,
  isClean: isClean ?? item.isClean,
  conditions: conditions ?? item.conditions,
  actions: actions ?? item.actions,
  note: note ?? item.note,
);

InspectionItem _toggleCondition(InspectionItem item, InspectionCondition c) =>
    _copy(
      item,
      isClean: false,
      conditions: item.conditions.contains(c)
          ? ({...item.conditions}..remove(c))
          : {...item.conditions, c},
    );

InspectionItem _toggleAction(InspectionItem item, InspectionAction a) => _copy(
  item,
  isClean: false,
  actions: item.actions.contains(a)
      ? ({...item.actions}..remove(a))
      : {...item.actions, a},
);

InspectionItem _setClean(InspectionItem item) => _copy(
  item,
  isClean: !item.isClean,
  conditions: const {},
  actions: const {},
);

/// Acceptance inspection sheet of a node, in three views.
class InspectionSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const InspectionSection({
    required this.reportId,
    required this.node,
    required this.unitType,
    required this.isEditable,
    super.key,
  });

  /// Report.
  final String reportId;

  /// Node holding the sheet.
  final ReportNode node;

  /// Unit type choosing the typical list.
  final String unitType;

  /// Whether the sheet can be changed.
  final bool isEditable;

  @override
  ConsumerState<InspectionSection> createState() => _InspectionSectionState();
}

class _InspectionSectionState extends ConsumerState<InspectionSection> {
  _View _view = _View.list;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(reportRepositoryProvider)
        .readPreference(_viewKey);
    if (!mounted) return;
    for (final view in _View.values) {
      if (view.name == stored) setState(() => _view = view);
    }
  }

  void _select(_View view) {
    setState(() => _view = view);
    unawaited(
      ref.read(reportRepositoryProvider).writePreference(_viewKey, view.name),
    );
  }

  Future<void> _run(
    Future<Result<Object?, ReportFailure>> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action();
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  void _save(InspectionItem item) => unawaited(
    _run(
      () => ref
          .read(reportRepositoryProvider)
          .saveInspectionItem(widget.reportId, item),
    ),
  );

  Future<void> _addItem() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Свой узел'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _run(
      () => ref
          .read(reportRepositoryProvider)
          .addInspectionItem(widget.reportId, widget.node.id, name),
    );
  }

  Future<void> _openSheet(int start) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ItemSheet(
      reportId: widget.reportId,
      nodeId: widget.node.id,
      start: start,
      isEditable: widget.isEditable,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final items = widget.node.inspection;
    if (items.isEmpty) {
      if (!widget.isEditable) return const SizedBox.shrink();
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: () => unawaited(
            _run(
              () => ref
                  .read(reportRepositoryProvider)
                  .seedInspection(
                    widget.reportId,
                    widget.node.id,
                    widget.unitType,
                  ),
            ),
          ),
          icon: const Icon(Icons.checklist),
          label: const Text('Заполнить ведомость осмотра'),
        ),
      );
    }
    final done = items.where((i) => i.isInspected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ведомость осмотра · осмотрено $done из ${items.length}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<_View>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _View.list, label: Text('Список')),
            ButtonSegment(value: _View.table, label: Text('Таблица')),
            ButtonSegment(value: _View.cards, label: Text('Карточки')),
          ],
          selected: {_view},
          onSelectionChanged: (set) => _select(set.first),
        ),
        const SizedBox(height: 8),
        switch (_view) {
          _View.list => Column(
            children: [
              for (final (index, item) in items.indexed)
                ListTile(
                  contentPadding: EdgeInsetsDirectional.zero,
                  minTileHeight: 64,
                  leading: Icon(
                    item.isInspected
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  title: Text(item.name),
                  subtitle: item.isInspected ? Text(item.summary) : null,
                  onTap: () => unawaited(_openSheet(index)),
                ),
            ],
          ),
          _View.table => _SheetTable(
            items: items,
            isEditable: widget.isEditable,
            onChanged: _save,
          ),
          _View.cards => Column(
            children: [
              for (final item in items)
                Card(
                  key: ValueKey(item.id),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _ItemEditor(
                      item: item,
                      isEditable: widget.isEditable,
                      onChanged: _save,
                    ),
                  ),
                ),
            ],
          ),
        },
        if (widget.isEditable)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => unawaited(
                  _run(
                    () => ref
                        .read(reportRepositoryProvider)
                        .markRestClean(widget.reportId, widget.node.id),
                  ),
                ),
                icon: const Icon(Icons.done_all),
                label: const Text('Остальные — без замечаний'),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_addItem()),
                icon: const Icon(Icons.add),
                label: const Text('Свой узел'),
              ),
            ],
          ),
        const Divider(),
      ],
    );
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.item,
    required this.isEditable,
    required this.onChanged,
    super.key,
  });

  final InspectionItem item;
  final bool isEditable;
  final ValueChanged<InspectionItem> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FilterChip(
          label: const Text('✓ Без замечаний'),
          selected: item.isClean,
          onSelected: isEditable ? (_) => onChanged(_setClean(item)) : null,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: [
            for (final c in InspectionCondition.values)
              FilterChip(
                label: Text(c.label),
                selected: item.conditions.contains(c),
                onSelected: isEditable
                    ? (_) => onChanged(_toggleCondition(item, c))
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (final a in InspectionAction.values)
              ChoiceChip(
                label: Text(a.label),
                selected: item.actions.contains(a),
                onSelected: isEditable
                    ? (_) => onChanged(_toggleAction(item, a))
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('note-${item.id}'),
          initialValue: item.note,
          enabled: isEditable,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Примечание',
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (text) => onChanged(_copy(item, note: text)),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onChanged: (text) => _NoteDebounce.run(
            item.id,
            () => onChanged(_copy(item, note: text)),
          ),
        ),
      ],
    );
  }
}

/// Saves the note shortly after typing stops.
abstract final class _NoteDebounce {
  static final Map<String, Timer> _timers = {};

  static void run(String key, VoidCallback action) {
    _timers[key]?.cancel();
    _timers[key] = Timer(const Duration(milliseconds: 600), () {
      _timers.remove(key);
      action();
    });
  }
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({
    required this.reportId,
    required this.nodeId,
    required this.start,
    required this.isEditable,
  });

  final String reportId;
  final String nodeId;
  final int start;
  final bool isEditable;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  late int _index = widget.start;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(reportDetailProvider(widget.reportId)).value;
    final items =
        detail?.nodes
            .where((n) => n.id == widget.nodeId)
            .expand((n) => n.inspection)
            .toList() ??
        const <InspectionItem>[];
    if (items.isEmpty) return const SizedBox(height: 120);
    final index = _index.clamp(0, items.length - 1);
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ItemEditor(
                key: ValueKey(items[index].id),
                item: items[index],
                isEditable: widget.isEditable,
                onChanged: (item) => unawaited(
                  ref
                      .read(reportRepositoryProvider)
                      .saveInspectionItem(widget.reportId, item),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Предыдущий узел',
                    iconSize: 32,
                    onPressed: index > 0
                        ? () => setState(() => _index = index - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${index + 1} из ${items.length}'),
                  const Spacer(),
                  FilledButton(
                    onPressed: index < items.length - 1
                        ? () => setState(() => _index = index + 1)
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      index < items.length - 1 ? 'Следующий узел' : 'Готово',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTable extends StatelessWidget {
  const _SheetTable({
    required this.items,
    required this.isEditable,
    required this.onChanged,
  });

  final List<InspectionItem> items;
  final bool isEditable;
  final ValueChanged<InspectionItem> onChanged;

  Widget _mark(String mark, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: isEditable ? onTap : null,
      child: SizedBox(
        width: 72,
        height: 52,
        child: Center(child: Text(mark, style: const TextStyle(fontSize: 20))),
      ),
    ),
  );

  Widget _head(String text) => SizedBox(
    width: 72,
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final border = TableBorder.all(color: Theme.of(context).dividerColor);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The first column stays in place like on the paper form.
        SizedBox(
          width: 130,
          child: Table(
            border: border,
            children: [
              const TableRow(
                children: [SizedBox(height: 64, child: Center(child: Text('Узел')))],
              ),
              for (final item in items)
                TableRow(
                  children: [
                    SizedBox(
                      height: 52,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          item.name,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: border,
              defaultColumnWidth: const FixedColumnWidth(72),
              children: [
                TableRow(
                  children: [
                    for (final c in InspectionCondition.values)
                      SizedBox(height: 64, child: _head(c.label)),
                    for (final a in InspectionAction.values)
                      SizedBox(height: 64, child: _head(a.label)),
                  ],
                ),
                for (final item in items)
                  TableRow(
                    children: [
                      for (final c in InspectionCondition.values)
                        _mark(
                          item.conditions.contains(c) ? '✗' : '',
                          '${item.name}: ${c.label}',
                          () => onChanged(_toggleCondition(item, c)),
                        ),
                      for (final a in InspectionAction.values)
                        _mark(
                          item.actions.contains(a) ? '●' : '',
                          '${item.name}: ${a.label}',
                          () => onChanged(_toggleAction(item, a)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
