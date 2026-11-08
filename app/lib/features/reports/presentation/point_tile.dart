import 'dart:async';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/reports/application/report_print.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:engineer/features/reports/presentation/tolerance_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _shown(Reading? reading) {
  final value = reading?.value;
  return value == null ? '' : formatDecimal(value);
}

/// Measured parameter: tolerance, input and live check of the typed value.
class PointTile extends ConsumerStatefulWidget {
  /// Creates the tile.
  const PointTile({
    required this.reportId,
    required this.point,
    required this.isEditable,
    super.key,
  });

  /// Report holding the point.
  final String reportId;

  /// The point.
  final MeasurementPoint point;

  /// Whether readings may be added.
  final bool isEditable;

  @override
  ConsumerState<PointTile> createState() => _PointTileState();
}

class _PointTileState extends ConsumerState<PointTile> {
  late final TextEditingController _controller = TextEditingController(
    text: _shown(widget.point.latest),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(PointTile old) {
    super.didUpdateWidget(old);
    final latest = widget.point.latest?.valueText;
    if (!_focus.hasFocus && latest != old.point.latest?.valueText) {
      _controller.text = _shown(widget.point.latest);
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
    if (canonical != null && canonical == widget.point.latest?.valueText) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(reportRepositoryProvider)
        .addReading(widget.reportId, widget.point.id, text);
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failureText(failure))));
    }
  }

  Future<void> _showHistory() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.point.name),
        content: SingleChildScrollView(
          child: Text(
            [
              for (final reading in widget.point.readings)
                '${formatDate(reading.atUtcMs)} — ${_shown(reading)} ${widget.point.tolerance.unit}',
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
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
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 150,
                child: TextField(
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
                  textInputAction: TextInputAction.done,
                  style: Theme.of(context).textTheme.titleLarge,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixText: point.tolerance.unit,
                  ),
                  onSubmitted: (_) => unawaited(_save()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    final number = parseDecimal(value.text);
                    if (number == null) return const SizedBox.shrink();
                    return Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ToleranceBadge(
                        status: evaluateReading(number, point.tolerance),
                      ),
                    );
                  },
                ),
              ),
              if (point.readings.length > 1)
                IconButton(
                  tooltip: 'История замеров',
                  icon: Badge(
                    label: Text('${point.readings.length}'),
                    child: const Icon(Icons.history),
                  ),
                  onPressed: () => unawaited(_showHistory()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
