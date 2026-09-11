import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/epub_preparer.dart';
import 'package:path/path.dart' as p;

Future<File> _zipDirectory(Directory source,String name) async {
  final zip=File(p.join(source.parent.path,name));
  final result=await Process.run('zip',['-q','-X','-r',zip.path,'.'],workingDirectory:source.path);
  if(result.exitCode!=0)throw StateError('zip failed: ${result.stderr}');
  return zip;
}

Future<File> _maliciousTraversalZip(Directory temp) async {
  final zip=File(p.join(temp.path,'traversal.epub'));
  const script='import sys,zipfile\np=sys.argv[1]\nwith zipfile.ZipFile(p,"w") as z:z.writestr("../escape.xhtml",b"<html/>")';
  final result=await Process.run('python3',['-c',script,zip.path]);
  if(result.exitCode!=0)throw StateError('python zip failed: ${result.stderr}');
  return zip;
}

void main(){
  test('EPUB preparer extracts spine, fixed layout and sanitizes active content',() async {
    final temp=await Directory.systemTemp.createTemp('lume-epub-runtime-');
    addTearDown(()=>temp.delete(recursive:true));
    final src=Directory(p.join(temp.path,'src'))..createSync(recursive:true);
    Directory(p.join(src.path,'META-INF')).createSync(recursive:true);
    File(p.join(src.path,'META-INF','container.xml')).writeAsStringSync(
      '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>');
    Directory(p.join(src.path,'OEBPS')).createSync(recursive:true);
    File(p.join(src.path,'OEBPS','content.opf')).writeAsStringSync(
      '<package><metadata><meta property="rendition:layout">pre-paginated</meta></metadata>'
      '<manifest><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>');
    File(p.join(src.path,'OEBPS','chapter.xhtml')).writeAsStringSync(
      '<html><head><meta http-equiv="refresh" content="0;url=https://example.invalid/"/>'
      '<style>@import "https://example.invalid/a.css"; .x{background:url(https://example.invalid/x.png)}</style>'
      '</head><body onload="alert(1)"><script>alert(1)</script>'
      '<img src="https://example.invalid/x.png"/><a href="javascript:alert(1)">x</a>'
      '<svg><foreignObject><body>bad</body></foreignObject></svg></body></html>');
    final epub=await _zipDirectory(src,'sample.epub');
    final destination=Directory(p.join(temp.path,'out'));
    final prepared=await EpubPreparer().prepare(epub:epub,destination:destination);
    expect(prepared.spine,hasLength(1));
    expect(prepared.fixedLayout,isTrue);
    final chapter=await File(prepared.spine.single).readAsString();
    expect(chapter,contains('about:blank'));
    expect(chapter.toLowerCase(),isNot(contains('<script')));
    expect(chapter.toLowerCase(),isNot(contains('foreignobject')));
    expect(chapter.toLowerCase(),isNot(contains('http-equiv="refresh"')));
    expect(chapter.toLowerCase(),isNot(contains('onload=')));
    expect(chapter,isNot(contains('https://example.invalid')));
    expect(chapter.toLowerCase(),isNot(contains('javascript:alert')));
  });

  test('EPUB preparer rejects path traversal before extraction',() async {
    final temp=await Directory.systemTemp.createTemp('lume-epub-traversal-');
    addTearDown(()=>temp.delete(recursive:true));
    final epub=await _maliciousTraversalZip(temp);
    await expectLater(
      EpubPreparer().prepare(epub:epub,destination:Directory(p.join(temp.path,'out'))),
      throwsA(isA<EpubPrepareException>()),
    );
    expect(await File(p.join(temp.parent.path,'escape.xhtml')).exists(),isFalse);
  });

  test('EPUB preparer enforces total uncompressed budget',() async {
    final temp=await Directory.systemTemp.createTemp('lume-epub-budget-');
    addTearDown(()=>temp.delete(recursive:true));
    final src=Directory(p.join(temp.path,'src'))..createSync(recursive:true);
    Directory(p.join(src.path,'META-INF')).createSync(recursive:true);
    File(p.join(src.path,'META-INF','container.xml')).writeAsStringSync('x');
    final epub=await _zipDirectory(src,'budget.epub');
    await expectLater(
      EpubPreparer(maxUncompressedBytes:0).prepare(epub:epub,destination:Directory(p.join(temp.path,'out'))),
      throwsA(isA<EpubPrepareException>()),
    );
  });
}
