import 'package:engineer/features/reports/domain/tolerance.dart';

/// Kind of work a report covers; [code] is stored in the database.
enum ReportType {
  /// Full disassembly in the workshop.
  full('full', 'Полная разборка'),

  /// Partial disassembly: only the chosen nodes.
  partial('partial', 'Частичная разборка'),

  /// Visit to the customer.
  field('field', 'Выезд к заказчику'),

  /// Arrival and dispatch of a unit.
  arrival('arrival', 'Прибытие / отправка');

  const ReportType(this.code, this.label);

  /// Stored code.
  final String code;

  /// Russian name.
  final String label;

  /// Type stored as [code]; [full] for an unknown code.
  static ReportType fromCode(String code) =>
      values.firstWhere((t) => t.code == code, orElse: () => full);
}

/// Review status; after [approved] the report is locked.
enum ReportStatus {
  /// Being filled in.
  draft('draft', 'Черновик'),

  /// Handed in for review.
  review('review', 'На проверке'),

  /// Approved; editing is closed.
  approved('approved', 'Утверждён');

  const ReportStatus(this.code, this.label);

  /// Stored code.
  final String code;

  /// Russian name.
  final String label;

  /// Status stored as [code]; [draft] for an unknown code.
  static ReportStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => draft);

  /// Whether the report content can be changed.
  bool get isEditable => this == draft;
}

/// Allowed moves between statuses.
bool canMoveStatus(ReportStatus from, ReportStatus to) => switch ((from, to)) {
  (ReportStatus.draft, ReportStatus.review) => true,
  (ReportStatus.review, ReportStatus.draft) => true,
  (ReportStatus.review, ReportStatus.approved) => true,
  _ => false,
};

/// Why a report change was refused.
enum ReportFailure {
  /// The report is on review or approved.
  locked,

  /// The report or record does not exist.
  missing,

  /// The value is not a number.
  notNumber,

  /// The status cannot move that way.
  badTransition,

  /// The database or a file could not be written.
  storage,
}

/// Header fields of a report.
final class ReportHeader {
  /// Creates a header.
  const ReportHeader({
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    required this.machine,
    required this.manualId,
    required this.unitCode,
    required this.unitName,
    required this.unitType,
    required this.serialNo,
    required this.customer,
    required this.authorId,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });

  /// Report id.
  final String id;

  /// Kind of work.
  final ReportType type;

  /// Review status.
  final ReportStatus status;

  /// Short title shown in lists.
  final String title;

  /// Machine model.
  final String machine;

  /// Manual whose technical data the report uses.
  final String? manualId;

  /// Unit code in that manual.
  final String unitCode;

  /// Unit name.
  final String unitName;

  /// Unit type (`ДВС`, `КПП`).
  final String unitType;

  /// Serial number of the unit.
  final String serialNo;

  /// Customer.
  final String customer;

  /// Author of the report.
  final String authorId;

  /// Creation time, UTC milliseconds.
  final int createdAtUtcMs;

  /// Last change, UTC milliseconds.
  final int updatedAtUtcMs;
}

/// One reading of a point.
final class Reading {
  /// Creates a reading.
  const Reading({
    required this.valueText,
    required this.authorId,
    required this.atUtcMs,
  });

  /// Canonical decimal text.
  final String valueText;

  /// Who measured.
  final String authorId;

  /// When, UTC milliseconds.
  final int atUtcMs;

  /// Numeric value; null only for corrupted data.
  double? get value => parseDecimal(valueText);
}

/// Measured parameter of a node with its readings, newest first.
final class MeasurementPoint {
  /// Creates a point.
  const MeasurementPoint({
    required this.id,
    required this.name,
    required this.tolerance,
    required this.readings,
  });

  /// Record id.
  final String id;

  /// Parameter name.
  final String name;

  /// Tolerance to check against.
  final Tolerance tolerance;

  /// Readings, newest first.
  final List<Reading> readings;

  /// Reading that goes into the report.
  Reading? get latest => readings.isEmpty ? null : readings.first;

  /// Status of [latest]; null when there is no reading.
  ToleranceStatus? get status {
    final value = latest?.value;
    return value == null ? null : evaluateReading(value, tolerance);
  }
}

/// Annotation mark on a photo, in coordinates relative to the image (0…1).
final class PhotoMark {
  /// Creates a mark.
  const PhotoMark({
    required this.tool,
    required this.color,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.text = '',
  });

  /// Shape.
  final MarkTool tool;

  /// Colour.
  final MarkColor color;

  /// Start x.
  final double x1;

  /// Start y.
  final double y1;

  /// End x.
  final double x2;

  /// End y.
  final double y2;

  /// Caption of a text mark.
  final String text;

  /// JSON form.
  Map<String, Object> toJson() => {
    'tool': tool.name,
    'color': color.name,
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    if (text.isNotEmpty) 'text': text,
  };
}

/// Mark read from JSON; null when malformed.
PhotoMark? parsePhotoMark(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final tool = MarkTool.values.where((t) => t.name == json['tool']);
  final color = MarkColor.values.where((c) => c.name == json['color']);
  double? n(String key) {
    final v = json[key];
    return v is num ? v.toDouble() : null;
  }

  final x1 = n('x1');
  final y1 = n('y1');
  final x2 = n('x2');
  final y2 = n('y2');
  if (tool.isEmpty || color.isEmpty) return null;
  if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
  final text = json['text'];
  return PhotoMark(
    tool: tool.first,
    color: color.first,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    text: text is String ? text : '',
  );
}

/// Shape of a photo mark.
enum MarkTool {
  /// Arrow from start to end.
  arrow('Стрелка'),

  /// Circle inscribed in the start–end box.
  circle('Круг'),

  /// Straight line.
  line('Линия'),

  /// Text at the start point.
  text('Текст');

  const MarkTool(this.label);

  /// Russian name.
  final String label;
}

/// Colour of a photo mark.
enum MarkColor {
  /// Red.
  red('Красный'),

  /// Yellow.
  yellow('Жёлтый'),

  /// Green.
  green('Зелёный');

  const MarkColor(this.label);

  /// Russian name.
  final String label;
}

/// Photo attached to a node; the original file is never changed.
final class ReportPhoto {
  /// Creates a photo.
  const ReportPhoto({
    required this.id,
    required this.originalPath,
    required this.annotatedPath,
    required this.caption,
    required this.marks,
    required this.pointId,
  });

  /// Record id.
  final String id;

  /// Absolute path of the original.
  final String originalPath;

  /// Absolute path of the copy with marks; null without marks.
  final String? annotatedPath;

  /// Explanation.
  final String caption;

  /// Marks drawn over the original.
  final List<PhotoMark> marks;

  /// Measurement point the photo belongs to, if any.
  final String? pointId;

  /// File to show and print.
  String get displayPath => annotatedPath ?? originalPath;
}

/// Node (part or assembly) of a report.
final class ReportNode {
  /// Creates a node.
  const ReportNode({
    required this.id,
    required this.title,
    required this.procCode,
    required this.remark,
    required this.points,
    required this.photos,
  });

  /// Record id.
  final String id;

  /// Node title.
  final String title;

  /// Factory page code of its procedure, may be empty.
  final String procCode;

  /// Engineer's remark.
  final String remark;

  /// Measured parameters.
  final List<MeasurementPoint> points;

  /// Photos.
  final List<ReportPhoto> photos;

  /// Whether the node has anything to print.
  bool get hasContent =>
      remark.trim().isNotEmpty ||
      photos.isNotEmpty ||
      points.any((p) => p.latest != null);
}

/// Report with its content.
final class ReportDetail {
  /// Creates a detail.
  const ReportDetail({required this.header, required this.nodes});

  /// Header.
  final ReportHeader header;

  /// Nodes in template order.
  final List<ReportNode> nodes;
}

/// Report row in the list.
final class ReportSummary {
  /// Creates a summary.
  const ReportSummary({
    required this.header,
    required this.measured,
    required this.outside,
  });

  /// Header.
  final ReportHeader header;

  /// Number of points with a reading.
  final int measured;

  /// Number of points outside the tolerance.
  final int outside;
}

/// Unit a report can be created for, with its technical data.
final class UnitOption {
  /// Creates an option.
  const UnitOption({
    required this.manualId,
    required this.machine,
    required this.code,
    required this.name,
    required this.unitType,
    required this.specCount,
  });

  /// Manual holding the data.
  final String manualId;

  /// Machine model.
  final String machine;

  /// Unit code.
  final String code;

  /// Unit name.
  final String name;

  /// Unit type.
  final String unitType;

  /// Number of tolerances for the unit.
  final int specCount;
}

/// Tolerance or torque from technical data.
final class TechSpec {
  /// Creates an entry.
  const TechSpec({
    required this.id,
    required this.name,
    required this.tolerance,
    required this.isTorque,
    required this.torqueText,
    required this.procKey,
    required this.procTitle,
    required this.procCode,
    required this.page,
  });

  /// Entry id.
  final String id;

  /// Parameter name.
  final String name;

  /// Tolerance.
  final Tolerance tolerance;

  /// Whether this is a tightening torque.
  final bool isTorque;

  /// Torque as printed.
  final String torqueText;

  /// Procedure key.
  final String procKey;

  /// Procedure title.
  final String procTitle;

  /// Factory page code.
  final String procCode;

  /// Source page.
  final int? page;
}

/// Group of tolerances of one procedure: becomes a report node.
final class TechNode {
  /// Creates a group.
  const TechNode({
    required this.procKey,
    required this.title,
    required this.code,
    required this.specs,
  });

  /// Procedure key.
  final String procKey;

  /// Procedure title.
  final String title;

  /// Factory page code.
  final String code;

  /// Tolerances of the procedure.
  final List<TechSpec> specs;
}

/// Data for a new report.
final class NewReport {
  /// Creates the data.
  const NewReport({
    required this.type,
    required this.machine,
    required this.unit,
    required this.serialNo,
    required this.customer,
    required this.selectedProcKeys,
  });

  /// Kind of work.
  final ReportType type;

  /// Machine model.
  final String machine;

  /// Unit with technical data; null for a unit without data.
  final UnitOption? unit;

  /// Serial number.
  final String serialNo;

  /// Customer.
  final String customer;

  /// Procedures chosen for a partial disassembly.
  final Set<String> selectedProcKeys;
}
