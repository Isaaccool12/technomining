import 'dart:async';
import 'dart:io';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/report_repository.dart';
import 'package:engineer/features/reports/domain/report_templates.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:engineer/features/reports/presentation/photo_annotate_screen.dart';
import 'package:engineer/features/reports/presentation/point_tile.dart';
import 'package:engineer/features/reports/presentation/tolerance_badge.dart';
import 'package:flutter/material.dart' hide Tolerance;
import 'package:flutter_riverpod/flutter_riverpod.dart';

void _showFailure(ScaffoldMessengerState messenger, Result<Object?, ReportFailure> result) {
  if (result case Err(:final failure)) {
    messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
  }
}

/// One report: nodes, measurements, photos, status and PDF.
class ReportScreen extends ConsumerWidget {
  /// Creates the screen.
  const ReportScreen({required this.reportId, super.key});

  /// Report to show.
  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportDetailProvider(reportId));
    final detail = async.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.header.type.label ?? 'Отчёт'),
        actions: [
          if (detail != null)
            IconButton(
              iconSize: 30,
              tooltip: 'PDF-отчёт',
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () => unawaited(_sharePdf(context, ref, detail)),
            ),
        ],
      ),
      floatingActionButton: detail != null && detail.header.status.isEditable
          ? FloatingActionButton.extended(
              heroTag: 'add-node',
              onPressed: () => unawaited(_addNode(context, ref, detail)),
              icon: const Icon(Icons.add),
              label: const Text('Узел'),
            )
          : null,
      bottomNavigationBar: detail == null ? null : _StatusBar(detail: detail),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorRetryView(
          onRetry: () => ref.invalidate(reportDetailProvider(reportId)),
        ),
        data: (detail) => detail == null
            ? const MessageView(icon: Icons.delete, title: 'Отчёт удалён')
            : ListView(
                padding: const EdgeInsetsDirectional.only(bottom: 120),
                children: [
                  _HeaderCard(detail: detail),
                  for (final node in detail.nodes)
                    _NodeCard(
                      key: ValueKey(node.id),
                      header: detail.header,
                      node: node,
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _sharePdf(
    BuildContext context,
    WidgetRef ref,
    ReportDetail detail,
  ) async {
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(const SnackBar(content: Text('Формирую PDF…')));
    final result = await exportReportPdf(
      detail,
      ref.read(reportRepositoryProvider),
      DateTime.now(),
    );
    switch (result) {
      case Ok(:final value):
        await ref.read(fileSharerProvider).share(value, 'application/pdf');
      case Err(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  Future<void> _addNode(
    BuildContext context,
    WidgetRef ref,
    ReportDetail detail,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final h = detail.header;
    final manualId = h.manualId;
    final specs = manualId == null
        ? const <TechSpec>[]
        : await ref
              .read(reportRepositoryProvider)
              .unitSpecs(manualId, h.unitCode);
    final used = detail.nodes.map((n) => n.title).toSet();
    final nodes = groupTechNodes(
      specs,
    ).where((n) => !used.contains(n.title)).toList();
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<_NodeChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddNodeSheet(nodes: nodes),
    );
    if (choice == null) return;
    final result = await ref
        .read(reportRepositoryProvider)
        .addNode(h.id, choice.title, from: choice.from);
    _showFailure(messenger, result);
  }
}

typedef _NodeChoice = ({String title, TechNode? from});

class _AddNodeSheet extends StatefulWidget {
  const _AddNodeSheet({required this.nodes});

  final List<TechNode> nodes;

  @override
  State<_AddNodeSheet> createState() => _AddNodeSheetState();
}

class _AddNodeSheetState extends State<_AddNodeSheet> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Новый узел', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Название узла',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Добавить',
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    final title = _name.text.trim();
                    if (title.isEmpty) return;
                    Navigator.of(context).pop<_NodeChoice>((title: title, from: null));
                  },
                ),
              ),
            ),
            if (widget.nodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Или узел с допусками из инструкции:'),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final node in widget.nodes)
                      ListTile(
                        title: Text(node.title),
                        subtitle: Text(
                          '${node.code} · допусков: ${node.specs.length}',
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop<_NodeChoice>((title: node.title, from: node)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail});

  final ReportDetail detail;

  @override
  Widget build(BuildContext context) {
    final h = detail.header;
    final statuses = detail.nodes
        .expand((n) => n.points)
        .map((p) => p.status)
        .whereType<ToleranceStatus>()
        .toList();
    int count(ToleranceStatus s) => statuses.where((x) => x == s).length;
    final rows = [
      ('Машина', h.machine),
      ('Агрегат', [h.unitName, h.unitType].where((s) => s.isNotEmpty).join(' · ')),
      ('Заводской №', h.serialNo),
      ('Заказчик', h.customer),
    ].where((r) => r.$2.trim().isNotEmpty);
    return Card(
      margin: const EdgeInsetsDirectional.all(12),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(h.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Chip(
              avatar: Icon(
                h.status.isEditable ? Icons.edit_note : Icons.lock,
                size: 20,
              ),
              label: Text(h.status.label),
            ),
            for (final (label, value) in rows) Text('$label: $value'),
            if (!h.status.isEditable)
              const Padding(
                padding: EdgeInsetsDirectional.only(top: 8),
                child: Text('Правки закрыты: отчёт на проверке или утверждён.'),
              ),
            if (statuses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in [
                    ToleranceStatus.within,
                    ToleranceStatus.nearLimit,
                    ToleranceStatus.outside,
                  ])
                    if (count(s) > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ToleranceBadge(status: s),
                          Text('  ${count(s)}'),
                        ],
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NodeCard extends ConsumerStatefulWidget {
  const _NodeCard({required this.header, required this.node, super.key});

  final ReportHeader header;
  final ReportNode node;

  @override
  ConsumerState<_NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends ConsumerState<_NodeCard> {
  late final TextEditingController _remark = TextEditingController(
    text: widget.node.remark,
  );
  final FocusNode _remarkFocus = FocusNode();

  ReportRepository get _repository => ref.read(reportRepositoryProvider);
  bool get _editable => widget.header.status.isEditable;
  String get _reportId => widget.header.id;

  @override
  void initState() {
    super.initState();
    _remarkFocus.addListener(_onRemarkFocus);
  }

  @override
  void didUpdateWidget(_NodeCard old) {
    super.didUpdateWidget(old);
    if (!_remarkFocus.hasFocus && widget.node.remark != _remark.text) {
      _remark.text = widget.node.remark;
    }
  }

  @override
  void dispose() {
    _remarkFocus
      ..removeListener(_onRemarkFocus)
      ..dispose();
    _remark.dispose();
    super.dispose();
  }

  void _onRemarkFocus() {
    if (_remarkFocus.hasFocus || _remark.text == widget.node.remark) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      _repository
          .setRemark(_reportId, widget.node.id, _remark.text)
          .then((result) => _showFailure(messenger, result)),
    );
  }

  Future<void> _addPhoto({required bool fromCamera}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final path = await ref.read(photoSourceProvider).pick(fromCamera: fromCamera);
    if (path == null) return;
    final result = await navigator.push<AnnotationResult>(
      MaterialPageRoute(
        builder: (_) => PhotoAnnotateScreen(
          imagePath: path,
          marks: const [],
          caption: '',
          isEditable: true,
        ),
      ),
    );
    if (result == null) return;
    final saved = await _repository.addPhoto(
      _reportId,
      widget.node.id,
      path,
      PhotoInput(
        caption: result.caption,
        marks: result.marks,
        annotatedPng: result.png,
      ),
    );
    _showFailure(messenger, saved);
  }

  Future<void> _openPhoto(ReportPhoto photo) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Navigator.of(context).push<AnnotationResult>(
      MaterialPageRoute(
        builder: (_) => PhotoAnnotateScreen(
          imagePath: photo.originalPath,
          marks: photo.marks,
          caption: photo.caption,
          isEditable: _editable,
        ),
      ),
    );
    if (result == null) return;
    final saved = await _repository.updatePhoto(
      _reportId,
      photo.id,
      PhotoInput(
        caption: result.caption,
        marks: result.marks,
        annotatedPng: result.png,
        pointId: photo.pointId,
      ),
    );
    _showFailure(messenger, saved);
  }

  Future<void> _remove(String recordId, String what) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Убрать $what?'),
        content: const Text('Запись скроется из отчёта, в базе она сохранится.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    _showFailure(messenger, await _repository.removeRecord(_reportId, recordId));
  }

  Future<void> _addPoint() async {
    final messenger = ScaffoldMessenger.of(context);
    final point = await showDialog<({String name, TechSpec spec})>(
      context: context,
      builder: (_) => const _ManualPointDialog(),
    );
    if (point == null) return;
    _showFailure(
      messenger,
      await _repository.addPoint(_reportId, widget.node.id, point.name, point.spec),
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final statuses = node.points.map((p) => p.status).whereType<ToleranceStatus>();
    final worst = statuses.contains(ToleranceStatus.outside)
        ? ToleranceStatus.outside
        : statuses.contains(ToleranceStatus.nearLimit)
        ? ToleranceStatus.nearLimit
        : null;
    final measured = node.points.where((p) => p.latest != null).length;
    final subtitle = [
      if (node.procCode.isNotEmpty) node.procCode,
      if (node.points.isNotEmpty) 'замеры: $measured из ${node.points.length}',
      if (node.photos.isNotEmpty) 'фото: ${node.photos.length}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        maintainState: true,
        title: Text(node.title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        leading: worst == null
            ? Icon(measured > 0 ? Icons.check_circle_outline : Icons.circle_outlined)
            : Icon(
                statusStyle(worst, Theme.of(context).brightness).icon,
                color: statusStyle(worst, Theme.of(context).brightness).background,
              ),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final point in node.points)
            GestureDetector(
              onLongPress: _editable
                  ? () => unawaited(_remove(point.id, 'замер «${point.name}»'))
                  : null,
              child: PointTile(
                key: ValueKey(point.id),
                reportId: _reportId,
                point: point,
                isEditable: _editable,
              ),
            ),
          if (node.photos.isNotEmpty)
            SizedBox(
              height: 112,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final photo in node.photos)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8, top: 8),
                      child: InkWell(
                        onTap: () => unawaited(_openPhoto(photo)),
                        onLongPress: _editable
                            ? () => unawaited(_remove(photo.id, 'фото'))
                            : null,
                        child: Semantics(
                          label: photo.caption.isEmpty ? 'Фото' : photo.caption,
                          child: Image.file(
                            File(photo.displayPath),
                            width: 136,
                            height: 104,
                            fit: BoxFit.cover,
                            cacheWidth: 272,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 136,
                              child: Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _remark,
            focusNode: _remarkFocus,
            enabled: _editable,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Замечание по узлу',
              border: OutlineInputBorder(),
            ),
          ),
          if (_editable) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => unawaited(_addPhoto(fromCamera: true)),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Фото'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_addPhoto(fromCamera: false)),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Галерея'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_addPoint()),
                  icon: const Icon(Icons.straighten),
                  label: const Text('Замер'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_remove(node.id, 'узел «${node.title}»')),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Убрать узел'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualPointDialog extends StatefulWidget {
  const _ManualPointDialog();

  @override
  State<_ManualPointDialog> createState() => _ManualPointDialogState();
}

class _ManualPointDialogState extends State<_ManualPointDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _unit = TextEditingController(text: 'мм');
  final TextEditingController _min = TextEditingController();
  final TextEditingController _max = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final spec = TechSpec(
      id: 'manual',
      name: name,
      tolerance: Tolerance(
        unit: _unit.text.trim(),
        min: parseDecimal(_min.text),
        max: parseDecimal(_max.text),
      ),
      isTorque: false,
      torqueText: '',
      procKey: '',
      procTitle: '',
      procCode: '',
      page: null,
    );
    Navigator.of(context).pop((name: name, spec: spec));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новый замер'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_name, 'Параметр'),
          _field(_unit, 'Единица'),
          _field(_min, 'Допуск: мин. (необязательно)', number: true),
          _field(_max, 'Допуск: макс. (необязательно)', number: true),
          const Text(
            'Ручной допуск действует только в этом отчёте. '
            'Утверждение допусков — на следующих этапах.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Добавить')),
    ],
  );
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.detail});

  final ReportDetail detail;

  Future<void> _move(BuildContext context, WidgetRef ref, ReportStatus to) async {
    final messenger = ScaffoldMessenger.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    _showFailure(
      messenger,
      await ref.read(reportRepositoryProvider).setStatus(detail.header.id, to),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = detail.header.status;
    final buttons = switch (status) {
      ReportStatus.draft => [
        FilledButton.icon(
          onPressed: () => unawaited(_move(context, ref, ReportStatus.review)),
          icon: const Icon(Icons.send),
          label: const Text('Сдать на проверку'),
        ),
      ],
      ReportStatus.review => [
        OutlinedButton(
          onPressed: () => unawaited(_move(context, ref, ReportStatus.draft)),
          child: const Text('Вернуть на доработку'),
        ),
        FilledButton.icon(
          onPressed: () => unawaited(_move(context, ref, ReportStatus.approved)),
          icon: const Icon(Icons.verified),
          label: const Text('Утвердить'),
        ),
      ],
      ReportStatus.approved => const <Widget>[],
    };
    if (buttons.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: buttons,
        ),
      ),
    );
  }
}
