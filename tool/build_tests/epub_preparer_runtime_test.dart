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
      '<html><body><script>alert(1)</script><img src="https://example.invalid/x.png"/></body></html>');
    final epub=await _zipDirectory(src,'sample.epub');
    final destination=Directory(p.join(temp.path,'out'));
    final prepared=await EpubPreparer().prepare(epub:epub,destination:destination);
    expect(prepared.spine,hasLength(1));
    expect(prepared.fixedLayout,isTrue);
    final chapter=await File(prepared.spine.single).readAsString();
    expect(chapter,contains('about:blank'));
    expect(chapter,contains('<script'),isFalse);
    expect(chapter,contains('https://example.invalid'),isFalse);
  });
}
