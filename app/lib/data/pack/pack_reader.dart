import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:engineer/core/result.dart';
import 'package:engineer/core/search_text.dart';
import 'package:engineer/data/pack/techdata_parser.dart';
import 'package:engineer/features/library/domain/library_models.dart';
import 'package:path/path.dart' as p;

final RegExp _procEntry = RegExp(r'^proc/([A-Za-z0-9_-][A-Za-z0-9._-]*)\.html$');
final RegExp _imageEntry = RegExp(
  r'^img/([A-Za-z0-9_-][A-Za-z0-9._-]*\.(?:jpg|jpeg|png|webp|gif))$',
);
final RegExp _unsafeDirChars = RegExp('[^A-Za-z0-9._-]');

/// Highest pack format version this app understands.
const int supportedPackVersion = 1;

/// A procedure read from a pack.
final class ParsedProcedure {
  /// Creates a parsed procedure.
  const ParsedProcedure({
    required this.key,
    required this.code,
    required this.title,
    required this.sectionTitle,
    required this.sortOrder,
    required this.pageFrom,
    required this.pageTo,
    required this.tier,
    required this.rawText,
    required this.titleIndex,
    required this.bodyIndex,
  });

  /// Key inside the pack.
  final String key;

  /// Factory page code.
  final String code;

  /// Title.
  final String title;

  /// Section title.
  final String sectionTitle;

  /// Position in the manual.
  final int sortOrder;

  /// First source page.
  final int? pageFrom;

  /// Last source page.
  final int? pageTo;

  /// Storage tier: `local` or `online`.
  final String tier;

  /// Source text used for snippets.
  final String rawText;

  /// Normalized title for the index.
  final String titleIndex;

  /// Normalized body for the index.
  final String bodyIndex;
}

/// Metadata and contents of a pack.
final class ParsedPack {
  /// Creates a parsed pack.
  const ParsedPack({
    required this.id,
    required this.title,
    required this.language,
    required this.documentCode,
    required this.machine,
    required this.aggregateCode,
    required this.source,
    required this.procedures,
    required this.imageNames,
    this.units = const [],
    this.specs = const [],
  });

  /// Manual identifier.
  final String id;

  /// Manual title.
  final String title;

  /// Language code.
  final String language;

  /// Factory document number.
  final String documentCode;

  /// Machine model.
  final String machine;

  /// Unit code.
  final String aggregateCode;

  /// Origin of the pack.
  final String source;

  /// Procedures in manual order.
  final List<ParsedProcedure> procedures;

  /// Names of the images stored from this pack.
  final List<String> imageNames;

  /// Units the pack covers.
  final List<ParsedUnit> units;

  /// Tolerances and torques from `techdata.json`.
  final List<ParsedSpec> specs;
}

/// Directory name of a manual: its id without unsafe characters.
String manualDirectoryName(String manualId) =>
    manualId.replaceAll(_unsafeDirChars, '_');

/// Reads the pack at [zipPath] on a background isolate and stores its files
/// under [rootPath].
Future<Result<ParsedPack, ImportFailure>> readPack(
  String zipPath,
  String rootPath,
) => Isolate.run(() => _readPack(zipPath, rootPath));

Future<Result<ParsedPack, ImportFailure>> _readPack(
  String zipPath,
  String rootPath,
) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    return await _unpack(archive, rootPath);
  } on FileSystemException {
    return const Err(ImportFailure.storage);
  } on ArchiveException {
    return const Err(ImportFailure.notZip);
  } on FormatException {
    return const Err(ImportFailure.badFormat);
  } finally {
    await input.close();
  }
}

Future<Result<ParsedPack, ImportFailure>> _unpack(
  Archive archive,
  String rootPath,
) async {
  final index = _readJson(archive, 'index.json');
  if (index == null) return const Err(ImportFailure.badFormat);
  final format = index['format'];
  final version = index['version'];
  if (format != 'qs-manual-pack' || version is! int) {
    return const Err(ImportFailure.badFormat);
  }
  if (version > supportedPackVersion) {
    return const Err(ImportFailure.unsupportedVersion);
  }
  final search = _readJson(archive, 'search.json') ?? const <String, dynamic>{};
  final parsed = parsePackIndex(index, search);
  if (parsed == null) return const Err(ImportFailure.badFormat);
  final images = await _storeFiles(archive, rootPath, parsed.id);
  final techdata =
      _readJson(archive, 'techdata.json') ?? const <String, dynamic>{};
  final manual = index['manual'] as Map<String, dynamic>;
  final units = parsePackUnits(manual);
  return Ok(
    ParsedPack(
      id: parsed.id,
      title: parsed.title,
      language: parsed.language,
      documentCode: parsed.documentCode,
      machine: parsed.machine,
      aggregateCode: parsed.aggregateCode,
      source: parsed.source,
      procedures: parsed.procedures,
      imageNames: images,
      units: units,
      specs: parseTechdata(techdata, units.first.code),
    ),
  );
}

Map<String, dynamic>? _readJson(Archive archive, String name) {
  final bytes = archive.find(name)?.readBytes();
  if (bytes == null) return null;
  final decoded = jsonDecode(utf8.decode(bytes));
  return decoded is Map<String, dynamic> ? decoded : null;
}

Future<List<String>> _storeFiles(
  Archive archive,
  String rootPath,
  String manualId,
) async {
  final procDir = Directory(
    p.join(rootPath, 'proc', manualDirectoryName(manualId)),
  );
  final imageDir = Directory(p.join(rootPath, 'img'));
  await procDir.create(recursive: true);
  await imageDir.create(recursive: true);
  final images = <String>[];
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    final proc = _procEntry.firstMatch(entry.name);
    final image = _imageEntry.firstMatch(entry.name);
    if (proc != null) {
      await _write(entry, p.join(procDir.path, '${proc[1]}.html'));
    } else if (image != null) {
      final name = image[1] ?? '';
      final target = File(p.join(imageDir.path, name));
      if (!target.existsSync()) await _write(entry, target.path);
      images.add(name);
    }
  }
  return images;
}

Future<void> _write(ArchiveFile entry, String path) async {
  final bytes = entry.readBytes();
  if (bytes != null) await File(path).writeAsBytes(bytes, flush: true);
}

/// Parses `index.json` and `search.json`; null when the required fields are
/// absent. Never throws on malformed values.
ParsedPack? parsePackIndex(
  Map<String, dynamic> index,
  Map<String, dynamic> search,
) {
  final manual = index['manual'];
  final procs = index['procs'];
  final sections = index['sections'];
  if (manual is! Map<String, dynamic> ||
      procs is! Map<String, dynamic> ||
      sections is! List<dynamic>) {
    return null;
  }
  final id = _text(manual, 'id');
  final title = _text(manual, 'title');
  if (id.isEmpty || title.isEmpty) return null;
  return ParsedPack(
    id: id,
    title: title,
    language: _text(manual, 'lang'),
    documentCode: _text(manual, 'doc'),
    machine: _text(manual, 'machine'),
    aggregateCode: _text(manual, 'agg'),
    source: _text(manual, 'source'),
    procedures: _parseProcedures(sections, procs, search),
    imageNames: const [],
  );
}

List<ParsedProcedure> _parseProcedures(
  List<dynamic> sections,
  Map<String, dynamic> procs,
  Map<String, dynamic> search,
) {
  final result = <ParsedProcedure>[];
  final seen = <String>{};
  for (final section in sections.whereType<Map<String, dynamic>>()) {
    final keys = section['procs'];
    if (keys is! List<dynamic>) continue;
    final sectionTitle = _text(section, 'title');
    for (final key in keys.whereType<String>()) {
      final meta = procs[key];
      if (meta is! Map<String, dynamic> || !seen.add(key)) continue;
      result.add(
        _parseProcedure(key, meta, sectionTitle, result.length, search[key]),
      );
    }
  }
  return result;
}

ParsedProcedure _parseProcedure(
  String key,
  Map<String, dynamic> meta,
  String sectionTitle,
  int order,
  Object? searchText,
) {
  final title = _text(meta, 'title');
  final raw = searchText is String ? searchText : title;
  final pages = meta['pages'];
  final pageList = pages is List<dynamic> ? pages.whereType<int>().toList() : <int>[];
  return ParsedProcedure(
    key: key,
    code: _text(meta, 'code'),
    title: title,
    sectionTitle: sectionTitle,
    sortOrder: order,
    pageFrom: pageList.isEmpty ? null : pageList.first,
    pageTo: pageList.isEmpty ? null : pageList.last,
    tier: meta['tier'] == 'online' ? 'online' : 'local',
    rawText: raw,
    titleIndex: normalizeForIndex(title),
    bodyIndex: normalizeForIndex(raw),
  );
}

String _text(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value : '';
}
