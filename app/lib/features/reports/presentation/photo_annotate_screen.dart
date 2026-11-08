import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:flutter/material.dart';

/// What the annotation screen returns.
final class AnnotationResult {
  /// Creates the result.
  const AnnotationResult({
    required this.marks,
    required this.caption,
    required this.png,
  });

  /// Marks over the original.
  final List<PhotoMark> marks;

  /// Explanation.
  final String caption;

  /// Copy with marks; null when there are no marks.
  final Uint8List? png;
}

/// Colour of a mark on screen and in the saved copy.
Color markColor(MarkColor color) => switch (color) {
  MarkColor.red => const Color(0xFFE53935),
  MarkColor.yellow => const Color(0xFFFFD600),
  MarkColor.green => const Color(0xFF43A047),
};

/// Draws marks over an image of [Size]; coordinates are relative.
class MarksPainter extends CustomPainter {
  /// Creates the painter.
  const MarksPainter(this.marks);

  /// Marks to draw.
  final List<PhotoMark> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(size.shortestSide * 0.008, 3).toDouble();
    for (final mark in marks) {
      final a = Offset(mark.x1 * size.width, mark.y1 * size.height);
      final b = Offset(mark.x2 * size.width, mark.y2 * size.height);
      final paint = Paint()
        ..color = markColor(mark.color)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      switch (mark.tool) {
        case MarkTool.line:
          canvas.drawLine(a, b, paint);
        case MarkTool.circle:
          canvas.drawOval(Rect.fromPoints(a, b), paint);
        case MarkTool.arrow:
          final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
          final head = math.max(stroke * 5, size.shortestSide * 0.035);
          Offset wing(double turn) =>
              b - Offset(math.cos(angle + turn), math.sin(angle + turn)) * head;
          canvas
            ..drawLine(a, b, paint)
            ..drawLine(b, wing(0.45), paint)
            ..drawLine(b, wing(-0.45), paint);
        case MarkTool.text:
          _drawText(canvas, size, mark, a);
      }
    }
  }

  void _drawText(Canvas canvas, Size size, PhotoMark mark, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: mark.text,
        style: TextStyle(
          color: markColor(mark.color),
          fontSize: math.max(size.shortestSide * 0.045, 14),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);
    final pad = painter.height * 0.2;
    final box = Rect.fromLTWH(
      at.dx - pad,
      at.dy - pad,
      painter.width + pad * 2,
      painter.height + pad * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(pad)),
      Paint()..color = const Color(0xB3000000),
    );
    painter
      ..paint(canvas, at)
      ..dispose();
  }

  @override
  bool shouldRepaint(MarksPainter oldDelegate) => oldDelegate.marks != marks;
}

/// Draws arrows, circles, lines and text over a photo. The original file is
/// never changed; the marks are returned with a rendered copy.
class PhotoAnnotateScreen extends StatefulWidget {
  /// Creates the screen.
  const PhotoAnnotateScreen({
    required this.imagePath,
    required this.marks,
    required this.caption,
    required this.isEditable,
    super.key,
  });

  /// Original photo.
  final String imagePath;

  /// Marks to start with.
  final List<PhotoMark> marks;

  /// Caption to start with.
  final String caption;

  /// Whether marks and caption may change.
  final bool isEditable;

  @override
  State<PhotoAnnotateScreen> createState() => _PhotoAnnotateState();
}

class _PhotoAnnotateState extends State<PhotoAnnotateScreen> {
  late List<PhotoMark> _marks = List.of(widget.marks);
  late final TextEditingController _caption = TextEditingController(
    text: widget.caption,
  );
  MarkTool _tool = MarkTool.arrow;
  MarkColor _color = MarkColor.red;
  PhotoMark? _current;
  ui.Image? _image;
  bool _showMarks = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Offset _relative(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0, 1).toDouble(),
    (local.dy / size.height).clamp(0, 1).toDouble(),
  );

  PhotoMark _mark(Offset a, Offset b, [String text = '']) => PhotoMark(
    tool: _tool,
    color: _color,
    x1: a.dx,
    y1: a.dy,
    x2: b.dx,
    y2: b.dy,
    text: text,
  );

  Future<void> _addText(Offset at) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подпись на фото'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _marks = [..._marks, _mark(at, at, text.trim())]);
  }

  Future<void> _done() async {
    final image = _image;
    if (image == null) return;
    setState(() => _saving = true);
    Uint8List? png;
    if (_marks.isNotEmpty) {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
      MarksPainter(_marks).paint(canvas, size);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(image.width, image.height);
      picture.dispose();
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      png = data?.buffer.asUint8List();
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      AnnotationResult(marks: _marks, caption: _caption.text.trim(), png: png),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final editable = widget.isEditable;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фото'),
        actions: [
          IconButton(
            tooltip: _showMarks ? 'Показать оригинал' : 'Показать пометки',
            icon: Icon(_showMarks ? Icons.layers_clear : Icons.layers),
            onPressed: () => setState(() => _showMarks = !_showMarks),
          ),
          if (editable)
            IconButton(
              tooltip: 'Отменить шаг',
              icon: const Icon(Icons.undo),
              onPressed: _marks.isEmpty
                  ? null
                  : () => setState(() => _marks = _marks.sublist(0, _marks.length - 1)),
            ),
          if (editable)
            IconButton(
              tooltip: 'Сохранить',
              icon: const Icon(Icons.check),
              onPressed: image == null || _saving ? null : () => unawaited(_done()),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: image == null
                ? const Center(child: CircularProgressIndicator())
                : _canvas(image),
          ),
          if (editable) _toolbar(),
          Padding(
            padding: const EdgeInsetsDirectional.all(12),
            child: TextField(
              controller: _caption,
              enabled: editable,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Пояснение',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvas(ui.Image image) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = math.min(
        constraints.maxWidth / image.width,
        constraints.maxHeight / image.height,
      );
      final size = Size(image.width * scale, image.height * scale);
      final current = _current;
      final shown = _showMarks
          ? [..._marks, if (current != null) current]
          : const <PhotoMark>[];
      return Center(
        child: SizedBox.fromSize(
          size: size,
          child: GestureDetector(
            onTapUp: widget.isEditable && _tool == MarkTool.text
                ? (d) => unawaited(_addText(_relative(d.localPosition, size)))
                : null,
            onPanStart: widget.isEditable && _tool != MarkTool.text
                ? (d) {
                    final at = _relative(d.localPosition, size);
                    setState(() => _current = _mark(at, at));
                  }
                : null,
            onPanUpdate: widget.isEditable && _tool != MarkTool.text
                ? (d) {
                    final start = _current;
                    if (start == null) return;
                    final at = _relative(d.localPosition, size);
                    setState(
                      () => _current = _mark(Offset(start.x1, start.y1), at),
                    );
                  }
                : null,
            onPanEnd: widget.isEditable && _tool != MarkTool.text
                ? (_) {
                    final mark = _current;
                    setState(() {
                      _current = null;
                      if (mark != null) _marks = [..._marks, mark];
                    });
                  }
                : null,
            child: CustomPaint(
              foregroundPainter: MarksPainter(shown),
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
        ),
      );
    },
  );

  Widget _toolbar() => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final tool in MarkTool.values)
          ChoiceChip(
            label: Text(tool.label),
            selected: _tool == tool,
            onSelected: (_) => setState(() => _tool = tool),
          ),
        for (final color in MarkColor.values)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: markColor(color)),
            label: Text(color.label),
            selected: _color == color,
            onSelected: (_) => setState(() => _color = color),
          ),
      ],
    ),
  );
}
