import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class PreparedEpub {
  final Directory root;
  final String packagePath;
  final List<String> spine;
  final bool fixedLayout;
  PreparedEpub(this.root, this.packagePath, this.spine, this.fixedLayout);
}

class EpubPrepareException implements Exception {
  final String message;
  const EpubPrepareException(this.message);
  @override String toString() => 'EpubPrepareException: $message';
}

class EpubPreparer {
  final int maxEntries;
  final int maxUncompressedBytes;
  EpubPreparer({this.maxEntries = 10000, this.maxUncompressedBytes = 500 * 1024 * 1024});

  Future<PreparedEpub> prepare({required File epub, required Directory destination}) async {
    if (!await epub.exists()) throw const EpubPrepareException('EPUB missing');
    final input = InputFileStream(epub.path);
    final archive = ZipDecoder().decodeStream(input);
    if (archive.length > maxEntries) throw const EpubPrepareException('too many entries');
    var total = 0;
    await destination.create(recursive: true);
    final rootCanonical = p.normalize(p.absolute(destination.path));
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.split('/').contains('..') || Uri.tryParse(name)?.hasScheme == true) {
        throw EpubPrepareException('unsafe archive path: $name');
      }
      total += entry.size;
      if (total > maxUncompressedBytes) throw const EpubPrepareException('archive too large');
      final outPath = p.normalize(p.absolute(p.join(destination.path, name)));
      if (!(outPath == rootCanonical || p.isWithin(rootCanonical, outPath))) {
        throw EpubPrepareException('path escapes destination: $name');
      }
      if (entry.isFile) {
        final out = File(outPath)..createSync(recursive: true);
        final data = entry.content;
        out.writeAsBytesSync(data, flush: false);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
    input.close();
    await _sanitizeLocalResources(destination);

    final container = File(p.join(destination.path, 'META-INF', 'container.xml'));
    if (!await container.exists()) throw const EpubPrepareException('container.xml missing');
    final cxml = await container.readAsString();
    final rootfile = RegExp(r'''full-path\s*=\s*["']([^"']+)["']''').firstMatch(cxml)?.group(1);
    if (rootfile == null || rootfile.isEmpty) throw const EpubPrepareException('rootfile missing');
    final opfFile = File(p.join(destination.path, rootfile));
    if (!await opfFile.exists()) throw const EpubPrepareException('OPF missing');
    final opf = await opfFile.readAsString();
    final manifest = <String, String>{};
    for (final m in RegExp(r'''<item\b[^>]*\bid=["']([^"']+)["'][^>]*\bhref=["']([^"']+)["'][^>]*/?>''', caseSensitive: false).allMatches(opf)) {
      manifest[m.group(1)!] = m.group(2)!;
    }
    final opfDir = p.dirname(rootfile);
    final spine = <String>[];
    for (final m in RegExp(r'''<itemref\b[^>]*\bidref=["']([^"']+)["'][^>]*/?>''', caseSensitive: false).allMatches(opf)) {
      final href = manifest[m.group(1)!];
      if (href == null) continue;
      final decoded = Uri.decodeComponent(href.split('#').first);
      final rel = p.normalize(p.join(opfDir, decoded));
      if (rel.startsWith('..') || p.isAbsolute(rel) || Uri.tryParse(decoded)?.hasScheme == true) {
        throw EpubPrepareException('unsafe spine href: $href');
      }
      final candidate = File(p.join(destination.path, rel));
      if (await candidate.exists()) spine.add(candidate.path);
    }
    if (spine.isEmpty) throw const EpubPrepareException('empty spine');
    final fixed = opf.contains('pre-paginated') || opf.contains('fixed-layout');
    return PreparedEpub(destination, rootfile, spine, fixed);
  }

  Future<void> _sanitizeLocalResources(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!const {'.xhtml', '.html', '.htm', '.svg', '.css'}.contains(ext)) continue;
      String text;
      try {
        text = await entity.readAsString();
      } catch (_) {
        continue;
      }
      if (ext == '.css') {
        // Block network fetches from @import and url(). Relative/local URLs survive.
        text = text
            .replaceAll(RegExp(r'''@import\s+(?:url\()?\s*["']?(?:https?|file|content|javascript):[^;\)]*\)?\s*;?''', caseSensitive: false), '/* blocked external import */')
            .replaceAllMapped(RegExp(r'''url\(\s*(["']?)(?:https?|file|content|javascript):[^\)]*\)''', caseSensitive: false), (_) => 'url(about:blank)')
            .replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), 'about:blank');
      } else {
        text = text
            .replaceAll(RegExp(r'<script\b[^>]*>[\s\S]*?</script\s*>', caseSensitive: false), '')
            .replaceAll(RegExp(r'<foreignObject\b[^>]*>[\s\S]*?</foreignObject\s*>', caseSensitive: false), '')
            .replaceAll(RegExp(r'''<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*>''', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s+on[a-z]+\s*=\s*\"[^\"]*\"', caseSensitive: false), '')
            .replaceAll(RegExp(r"\s+on[a-z]+\s*=\s*'[^']*'", caseSensitive: false), '')
            .replaceAll(RegExp(r'''@import\s+(?:url\()?\s*["']?(?:https?|file|content|javascript):[^;\)]*\)?\s*;?''', caseSensitive: false), '/* blocked external import */')
            .replaceAllMapped(RegExp(r'''url\(\s*(["']?)(?:https?|file|content|javascript):[^\)]*\)''', caseSensitive: false), (_) => 'url(about:blank)')
            .replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), 'about:blank:')
            .replaceAllMapped(RegExp(r'''((?:xlink:)?href|src)\s*=\s*(["'])(?:https?|file|content|javascript):[^"']*\2''', caseSensitive: false), (m) => '${m.group(1)}=${m.group(2)}about:blank${m.group(2)}')
            .replaceAllMapped(RegExp(r'''((?:xlink:)?href|src)\s*=\s*(["'])/[^"']*\2''', caseSensitive: false), (m) => '${m.group(1)}=${m.group(2)}about:blank${m.group(2)}');
      }
      await entity.writeAsString(text, flush: false);
    }
  }

}
