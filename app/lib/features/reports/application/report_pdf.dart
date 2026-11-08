import 'dart:typed_data';

import 'package:engineer/features/reports/application/report_print.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Fonts embedded into the report.
final class PdfFonts {
  /// Creates the set from TrueType data.
  const PdfFonts({required this.regular, required this.bold});

  /// Regular face.
  final ByteData regular;

  /// Bold face.
  final ByteData bold;
}

const PdfColor _accent = PdfColor.fromInt(0xFFB7791F);
const PdfColor _grey = PdfColor.fromInt(0xFF5F6368);
const PdfColor _line = PdfColor.fromInt(0xFF9AA0A6);

PdfColor _statusColor(ToleranceStatus status) => switch (status) {
  ToleranceStatus.within => const PdfColor.fromInt(0xFF1B5E20),
  ToleranceStatus.nearLimit => const PdfColor.fromInt(0xFF8D6E00),
  ToleranceStatus.outside => const PdfColor.fromInt(0xFFB71C1C),
  ToleranceStatus.noTolerance => _grey,
};

/// Renders [report] on the company letterhead. [photos] maps a photo path to
/// its bytes; a photo without bytes is skipped.
Future<Uint8List> buildReportPdf(
  PrintReport report,
  PdfFonts fonts, {
  required Map<String, Uint8List> photos,
  required String printedOn,
}) async {
  final doc = pw.Document(
    title: report.title,
    author: 'ТехноМайнинг',
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts.regular),
      bold: pw.Font.ttf(fonts.bold),
    ),
  )..addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      header: (context) => _letterhead(report.title),
      footer: (context) => _footer(context, printedOn),
      build: (context) => [
        _fieldsTable(report.fields),
        if (report.outsideCount > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Вне допуска: ${report.outsideCount}',
              style: pw.TextStyle(
                color: _statusColor(ToleranceStatus.outside),
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        for (final node in report.nodes) ..._node(node, photos),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _letterhead(String title) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 12),
  padding: const pw.EdgeInsets.only(bottom: 6),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 2)),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ТехноМайнинг',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: _accent,
            ),
          ),
          pw.Text(
            'Ремонт спецтехники и агрегатов',
            style: const pw.TextStyle(fontSize: 9, color: _grey),
          ),
        ],
      ),
      pw.Spacer(),
      pw.SizedBox(
        width: 260,
        child: pw.Text(
          title,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ],
  ),
);

pw.Widget _footer(pw.Context context, String printedOn) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 8),
  child: pw.Row(
    children: [
      pw.Text(
        'Сформировано $printedOn',
        style: const pw.TextStyle(fontSize: 8, color: _grey),
      ),
      pw.Spacer(),
      pw.Text(
        'Стр. ${context.pageNumber} из ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: _grey),
      ),
    ],
  ),
);

pw.Widget _cell(String text, {pw.TextStyle? style}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
  child: pw.Text(text, style: style ?? const pw.TextStyle(fontSize: 9.5)),
);

pw.Widget _fieldsTable(List<PrintField> fields) => pw.Table(
  border: pw.TableBorder.all(color: _line, width: 0.5),
  columnWidths: const {
    0: pw.FixedColumnWidth(130),
    1: pw.FlexColumnWidth(),
  },
  children: [
    for (final field in fields)
      pw.TableRow(
        children: [
          _cell(field.label, style: const pw.TextStyle(color: _grey)),
          _cell(field.value),
        ],
      ),
  ],
);

List<pw.Widget> _node(PrintNode node, Map<String, Uint8List> photos) {
  final bold = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);
  return [
    pw.Header(
      level: 2,
      margin: const pw.EdgeInsets.only(top: 14, bottom: 4),
      child: pw.Text(
        node.code.isEmpty ? node.title : '${node.title}  ·  ${node.code}',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ),
    if (node.remark.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(node.remark),
      ),
    if (node.points.isNotEmpty)
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(2.4),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF1F3F4),
            ),
            children: [
              _cell('Параметр', style: bold),
              _cell('Допуск', style: bold),
              _cell('Замер', style: bold),
              _cell('Оценка', style: bold),
            ],
          ),
          for (final point in node.points)
            pw.TableRow(
              children: [
                _cell(point.name),
                _cell(point.tolerance),
                _cell(point.value),
                _cell(
                  statusLabel(point.status),
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _statusColor(point.status),
                    fontWeight: point.status == ToleranceStatus.outside
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
        ],
      ),
    for (final photo in node.photos)
      if (photos[photo.displayPath] case final bytes?)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Image(
                pw.MemoryImage(bytes),
                height: 230,
                fit: pw.BoxFit.contain,
              ),
              if (photo.caption.trim().isNotEmpty)
                pw.Text(
                  'Пояснение: ${photo.caption.trim()}',
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
            ],
          ),
        ),
  ];
}
