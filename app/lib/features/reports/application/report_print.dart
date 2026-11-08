import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:intl/intl.dart';

/// Label and value of a filled header field.
typedef PrintField = ({String label, String value});

/// Measured parameter as printed.
typedef PrintPoint = ({
  String name,
  String tolerance,
  String value,
  ToleranceStatus status,
});

/// Node as printed: only what was filled in.
final class PrintNode {
  /// Creates a node.
  const PrintNode({
    required this.title,
    required this.code,
    required this.remark,
    required this.points,
    required this.photos,
  });

  /// Node title.
  final String title;

  /// Factory page code, may be empty.
  final String code;

  /// Remark, may be empty.
  final String remark;

  /// Measured parameters with a reading.
  final List<PrintPoint> points;

  /// Photos.
  final List<ReportPhoto> photos;
}

/// Report reduced to the data that goes on paper.
final class PrintReport {
  /// Creates the report.
  const PrintReport({
    required this.title,
    required this.fields,
    required this.nodes,
    required this.outsideCount,
  });

  /// Report title.
  final String title;

  /// Filled header fields.
  final List<PrintField> fields;

  /// Nodes with content.
  final List<PrintNode> nodes;

  /// Number of readings outside the tolerance.
  final int outsideCount;
}

/// Russian label of a check result, always with its sign.
String statusLabel(ToleranceStatus status) => switch (status) {
  ToleranceStatus.within => '✓ В допуске',
  ToleranceStatus.nearLimit => '! У предела',
  ToleranceStatus.outside => '✕ Вне допуска',
  ToleranceStatus.noTolerance => 'Без допуска',
};

/// Local date of [utcMs] as `dd.MM.yyyy`.
String formatDate(int utcMs) => DateFormat(
  'dd.MM.yyyy',
).format(DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).toLocal());

/// Builds what is printed: empty fields, unmeasured points and nodes without
/// content are left out.
PrintReport printableReport(ReportDetail detail) {
  final h = detail.header;
  final fields = <PrintField>[
    (label: 'Вид работ', value: h.type.label),
    (label: 'Машина', value: h.machine),
    (label: 'Агрегат', value: h.unitName),
    (label: 'Тип агрегата', value: h.unitType),
    (label: 'Заводской номер', value: h.serialNo),
    (label: 'Заказчик', value: h.customer),
    (label: 'Дата', value: formatDate(h.createdAtUtcMs)),
    (label: 'Статус', value: h.status.label),
  ].where((f) => f.value.trim().isNotEmpty).toList();
  var outside = 0;
  final nodes = <PrintNode>[];
  for (final node in detail.nodes) {
    if (!node.hasContent) continue;
    final points = <PrintPoint>[];
    for (final point in node.points) {
      final reading = point.latest;
      final value = reading?.value;
      final status = point.status;
      if (reading == null || value == null || status == null) continue;
      if (status == ToleranceStatus.outside) outside++;
      final unit = point.tolerance.unit;
      points.add((
        name: point.name,
        tolerance: describeTolerance(point.tolerance),
        value: unit.isEmpty
            ? formatDecimal(value)
            : '${formatDecimal(value)} $unit',
        status: status,
      ));
    }
    nodes.add(
      PrintNode(
        title: node.title,
        code: node.procCode,
        remark: node.remark.trim(),
        points: points,
        photos: node.photos,
      ),
    );
  }
  return PrintReport(
    title: h.title,
    fields: fields,
    nodes: nodes,
    outsideCount: outside,
  );
}
