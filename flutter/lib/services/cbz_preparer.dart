import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class PreparedCbz {
  final Directory root;
  final List<String> pages;
  const PreparedCbz(this.root,this.pages);
}

class CbzPrepareException implements Exception {
  final String message;
  const CbzPrepareException(this.message);
  @override String toString()=>'CbzPrepareException: $message';
}

class CbzPreparer {
  final int maxEntries;
  final int maxUncompressedBytes;
  final int maxPageBytes;
  CbzPreparer({
    this.maxEntries=5000,
    this.maxUncompressedBytes=1500*1024*1024,
    this.maxPageBytes=100*1024*1024,
  });

  static const imageExt={'.jpg','.jpeg','.png','.webp','.gif'};

  Future<PreparedCbz> prepare({required File cbz,required Directory destination}) async {
    if(!await cbz.exists())throw const CbzPrepareException('CBZ missing');
    final input=InputFileStream(cbz.path);
    try{
      final archive=ZipDecoder().decodeStream(input);
      if(archive.length>maxEntries)throw const CbzPrepareException('too many entries');
      var total=0;
      final pages=<String>[];
      await destination.create(recursive:true);
      final root=p.normalize(p.absolute(destination.path));
      for(final entry in archive){
        final name=entry.name.replaceAll('\\','/');
        if(name.startsWith('/') || name.split('/').contains('..') || Uri.tryParse(name)?.hasScheme==true){
          throw CbzPrepareException('unsafe archive path: $name');
        }
        if(!entry.isFile)continue;
        total+=entry.size;
        if(total>maxUncompressedBytes)throw const CbzPrepareException('archive too large');
        final ext=p.extension(name).toLowerCase();
        if(!imageExt.contains(ext))continue;
        if(entry.size>maxPageBytes)throw CbzPrepareException('page too large: $name');
        final outPath=p.normalize(p.absolute(p.join(destination.path,name)));
        if(!(outPath==root || p.isWithin(root,outPath)))throw CbzPrepareException('path escapes destination: $name');
        final data=entry.content;
        final out=File(outPath);
        await out.parent.create(recursive:true);
        await out.writeAsBytes(data,flush:false);
        pages.add(out.path);
      }
      if(pages.isEmpty)throw const CbzPrepareException('CBZ has no supported image pages');
      pages.sort(_naturalCompare);
      return PreparedCbz(destination,List.unmodifiable(pages));
    } finally {
      input.close();
    }
  }

  static int _naturalCompare(String a,String b){
    final aa=p.basename(a).toLowerCase();
    final bb=p.basename(b).toLowerCase();
    final rx=RegExp(r'(\d+|\D+)');
    final ap=rx.allMatches(aa).map((m)=>m.group(0)!).toList();
    final bp=rx.allMatches(bb).map((m)=>m.group(0)!).toList();
    for(var i=0;i<ap.length && i<bp.length;i++){
      final an=int.tryParse(ap[i]), bn=int.tryParse(bp[i]);
      final c=(an!=null && bn!=null) ? an.compareTo(bn) : ap[i].compareTo(bp[i]);
      if(c!=0)return c;
    }
    return ap.length.compareTo(bp.length);
  }

  Future<void> writeMarker(PreparedCbz prepared,File marker,String sourceTag) async {
    await marker.writeAsString(jsonEncode({
      'sourceTag':sourceTag,
      'pages':prepared.pages,
    }),flush:true);
  }
}
