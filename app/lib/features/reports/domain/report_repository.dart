import 'dart:typed_data';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/reports/domain/grid.dart';
import 'package:engineer/features/reports/domain/inspection.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';

/// Photo to attach or update.
final class PhotoInput {
  /// Creates the input.
  const PhotoInput({
    required this.caption,
    required this.marks,
    required this.annotatedPng,
    this.pointId,
  });

  /// Explanation.
  final String caption;

  /// Marks over the original.
  final List<PhotoMark> marks;

  /// Rendered copy with marks; null when there are none.
  final Uint8List? annotatedPng;

  /// Measurement point the photo belongs to.
  final String? pointId;
}

/// Reports, their records and the technical data they use.
abstract interface class ReportRepository {
  /// Reports, newest first.
  Stream<List<ReportSummary>> watchReports();

  /// One report with its content; null when deleted.
  Stream<ReportDetail?> watchReport(String reportId);

  /// Units with technical data from the imported packs.
  Future<List<UnitOption>> unitOptions();

  /// Tolerances and torques of a unit.
  Future<List<TechSpec>> unitSpecs(String manualId, String unitCode);

  /// Creates a report from its template; returns the new id.
  Future<Result<String, ReportFailure>> createReport(NewReport data);

  /// Adds a node, optionally with the tolerances of a procedure.
  Future<Result<String, ReportFailure>> addNode(
    String reportId,
    String title, {
    TechNode? from,
  });

  /// Adds a measurement point to [nodeId].
  Future<Result<String, ReportFailure>> addPoint(
    String reportId,
    String nodeId,
    String name,
    TechSpec? spec,
  );

  /// Records a new reading typed by the engineer.
  Future<Result<void, ReportFailure>> addReading(
    String reportId,
    String pointId,
    String typed,
  );

  /// Sets the remark of a node.
  Future<Result<void, ReportFailure>> setRemark(
    String reportId,
    String nodeId,
    String text,
  );

  /// Copies the picked file as the original and stores [input].
  Future<Result<String, ReportFailure>> addPhoto(
    String reportId,
    String nodeId,
    String sourcePath,
    PhotoInput input,
  );

  /// Replaces the marks and caption of a photo; the original stays.
  Future<Result<void, ReportFailure>> updatePhoto(
    String reportId,
    String photoId,
    PhotoInput input,
  );

  /// Hides a node, point or photo; nothing is erased.
  Future<Result<void, ReportFailure>> removeRecord(
    String reportId,
    String recordId,
  );

  /// Moves the report to [status].
  Future<Result<void, ReportFailure>> setStatus(
    String reportId,
    ReportStatus status,
  );

  /// Fills [nodeId] with the typical inspection list of the unit type.
  Future<Result<void, ReportFailure>> seedInspection(
    String reportId,
    String nodeId,
    String unitType,
  );

  /// Adds the engineer's own line to the inspection sheet.
  Future<Result<String, ReportFailure>> addInspectionItem(
    String reportId,
    String nodeId,
    String name,
  );

  /// Stores the result of a line.
  Future<Result<void, ReportFailure>> saveInspectionItem(
    String reportId,
    InspectionItem item,
  );

  /// Marks every line not yet inspected as "Без замечаний".
  Future<Result<void, ReportFailure>> markRestClean(
    String reportId,
    String nodeId,
  );

  /// Stores the composition of the unit.
  Future<Result<void, ReportFailure>> setComposition(
    String reportId,
    UnitComposition composition,
  );

  /// Adds a measurement grid to [nodeId].
  Future<Result<String, ReportFailure>> addGrid(
    String reportId,
    String nodeId,
    String name,
    GridSpec grid,
    Tolerance? tolerance,
  );

  /// Records a new reading of one grid cell.
  Future<Result<void, ReportFailure>> addCellReading(
    String reportId,
    String pointId,
    String cellKey,
    String typed,
  );

  /// Chooses the verdict on [row] by hand; null returns to automatic.
  Future<Result<void, ReportFailure>> setGrade(
    String reportId,
    String pointId,
    int row,
    PartGrade? grade,
  );

  /// Reads a remembered view choice.
  Future<String?> readPreference(String key);

  /// Remembers a view choice.
  Future<void> writePreference(String key, String value);

  /// Directory for generated PDF files.
  String get exportsDirectory;
}
