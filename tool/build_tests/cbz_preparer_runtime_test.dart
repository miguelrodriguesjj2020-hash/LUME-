import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/cbz_preparer.dart';
import 'package:path/path.dart' as p;

Future<File> _zipDirectory(Directory source,String name) async {
  final zip=File(p.join(source.parent.path,name));
  final result=await Process.run('zip',['-q','-X','-r',zip.path,'.'],workingDirectory:source.path);
  if(result.exitCode!=0)throw StateError('zip failed: ${result.stderr}');
  return zip;
}

void main(){
  test('CBZ preparer extracts image pages in natural numeric order',() async {
    final temp=await Directory.systemTemp.createTemp('lume-cbz-runtime-');
    addTearDown(()=>temp.delete(recursive:true));
    final src=Directory(p.join(temp.path,'src'))..createSync(recursive:true);
    await File(p.join(src.path,'page10.png')).writeAsBytes([10]);
    await File(p.join(src.path,'page2.png')).writeAsBytes([2]);
    await File(p.join(src.path,'page1.png')).writeAsBytes([1]);
    await File(p.join(src.path,'notes.txt')).writeAsString('ignored');
    final cbz=await _zipDirectory(src,'sample.cbz');
    final destination=Directory(p.join(temp.path,'out'));
    final prepared=await CbzPreparer().prepare(cbz:cbz,destination:destination);
    expect(prepared.pages.map(p.basename).toList(),['page1.png','page2.png','page10.png']);
    expect(await File(prepared.pages[0]).readAsBytes(),[1]);
    expect(await File(prepared.pages[2]).readAsBytes(),[10]);
  });
}
