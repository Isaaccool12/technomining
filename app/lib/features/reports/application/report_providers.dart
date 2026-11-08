import 'dart:io';
import 'dart:typed_data';

import 'package:engineer/core/result.dart';
import 'package:engineer/features/reports/application/report_pdf.dart';
import 'package:engineer/features/reports/application/report_print.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:engineer/features/reports/domain/report_repository.dart';
import 'package:engineer/features/reports/domain/report_services.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Report repository, provided at the composition root.
final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => throw UnimplementedError('Provided in bootstrap'),
);

/// Camera and gallery, provided at the composition root.
final photoSourceProvider = Provider<PhotoSource>(
  (ref) => throw UnimplementedError('Provided in bootstrap'),
);

/// System share sheet, provided at the composition root.
final fileSharerProvider = Provider<FileSharer>(
  (ref) => throw UnimplementedError('Provided in bootstrap'),
);

/// Reports, newest first.
final reportsProvider = StreamProvider.autoDispose<List<ReportSummary>>(
  (ref) => ref.watch(reportRepositoryProvider).watchReports(),
);

/// One report with its content.
final reportDetailProvider = StreamProvider.autoDispose
    .family<ReportDetail?, String>(
      (ref, id) => ref.watch(reportRepositoryProvider).watchReport(id),
    );

/// Units with technical data.
final unitOptionsProvider = FutureProvider.autoDispose<List<UnitOption>>(
  (ref) => ref.watch(reportRepositoryProvider).unitOptions(),
);

/// Identifies a unit inside a manual.
typedef UnitKey = ({String manualId, String unitCode});

/// Tolerances and torques of one unit.
final unitSpecsProvider = FutureProvider.autoDispose
    .family<List<TechSpec>, UnitKey>(
      (ref, key) => ref
          .watch(reportRepositoryProvider)
          .unitSpecs(key.manualId, key.unitCode),
    );

/// Russian text of a refused change.
String failureText(ReportFailure failure) => switch (failure) {
  ReportFailure.locked =>
    'Отчёт на проверке или утверждён — правки закрыты.',
  ReportFailure.missing => 'Запись не найдена.',
  ReportFailure.notNumber => 'Введите число, например 12,345.',
  ReportFailure.badTransition => 'Такой переход статуса недоступен.',
  ReportFailure.storage => 'Не удалось сохранить на устройстве.',
};

/// Builds the PDF of [detail], writes it next to the other exports and
/// returns its path.
Future<Result<String, ReportFailure>> exportReportPdf(
  ReportDetail detail,
  ReportRepository repository,
  DateTime now,
) async {
  try {
    final printable = printableReport(detail);
    final photos = <String, Uint8List>{};
    for (final node in printable.nodes) {
      for (final photo in node.photos) {
        final file = File(photo.displayPath);
        if (file.existsSync()) photos[photo.displayPath] = await file.readAsBytes();
      }
    }
    final fonts = PdfFonts(
      regular: await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
      bold: await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final bytes = await buildReportPdf(
      printable,
      fonts,
      photos: photos,
      printedOn: formatDate(now.toUtc().millisecondsSinceEpoch),
    );
    final directory = Directory(repository.exportsDirectory);
    await directory.create(recursive: true);
    final safe = detail.header.title
        .replaceAll(RegExp(r'[\\/:*?"<>|№]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final file = File(
      p.join(directory.path, '${safe.isEmpty ? 'Отчёт' : safe}.pdf'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return Ok(file.path);
  } on FileSystemException {
    return const Err(ReportFailure.storage);
  }
}
