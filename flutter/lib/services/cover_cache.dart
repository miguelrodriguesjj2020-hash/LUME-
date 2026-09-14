import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/catalog.dart';
import 'api.dart';

class CoverCacheException implements Exception {
  final String message;
  const CoverCacheException(this.message);
  @override String toString()=>'CoverCacheException: $message';
}

class CoverCache {
  final LumeApi api;
  final Directory directory;
  final Map<String,Future<File?>> _inflight={};

  CoverCache({required this.api,required this.directory});

  Future<File?> resolve(Work work)=>_inflight.putIfAbsent(work.id,()=>_resolve(work).whenComplete(()=>_inflight.remove(work.id)));

  Future<File?> _resolve(Work work) async {
    final cover=work.cover;
    if(cover==null)return null;
    if(!RegExp(r'^[a-zA-Z0-9-]{2,96}$').hasMatch(work.id))throw const CoverCacheException('unsafe work ID');
    await directory.create(recursive:true);
    final extension=switch(cover.mimeType){'image/png'=>'.png','image/webp'=>'.webp',_=>'.jpg'};
    final destination=File('${directory.path}/${work.id}-${cover.sha256.substring(0,16)}$extension');
    if(await _validFile(destination,cover))return destination;
    if(await destination.exists())await destination.delete();

    final descriptor=await api.cover(work.id);
    if(descriptor['sha256']!=cover.sha256 || descriptor['byteSize']!=cover.byteSize || descriptor['mimeType']!=cover.mimeType){
      throw const CoverCacheException('descriptor does not match catalog cover');
    }
    final rawUrl=descriptor['url'];
    if(rawUrl is! String)throw const CoverCacheException('cover URL missing');
    final uri=Uri.tryParse(rawUrl);
    if(uri==null || uri.scheme!='https')throw const CoverCacheException('cover URL must use HTTPS');
    final response=await api.client.get(uri);
    if(response.statusCode!=200)throw CoverCacheException('cover download failed: ${response.statusCode}');
    final bytes=response.bodyBytes;
    if(bytes.length!=cover.byteSize)throw const CoverCacheException('cover byte size mismatch');
    if(!_matchesSignature(bytes,cover.mimeType))throw const CoverCacheException('cover signature mismatch');
    if(sha256.convert(bytes).toString()!=cover.sha256)throw const CoverCacheException('cover SHA-256 mismatch');
    final temporary=File('${destination.path}.part');
    try{
      await temporary.writeAsBytes(bytes,flush:true);
      await temporary.rename(destination.path);
    }finally{
      if(await temporary.exists())await temporary.delete();
    }
    return destination;
  }

  Future<bool> _validFile(File file,CoverAsset cover) async {
    if(!await file.exists())return false;
    if(await file.length()!=cover.byteSize)return false;
    final bytes=await file.readAsBytes();
    return _matchesSignature(bytes,cover.mimeType)&&sha256.convert(bytes).toString()==cover.sha256;
  }

  bool _matchesSignature(List<int> bytes,String mimeType)=>switch(mimeType){
    'image/jpeg'=>bytes.length>=3&&bytes[0]==0xff&&bytes[1]==0xd8&&bytes[2]==0xff,
    'image/png'=>bytes.length>=8&&bytes[0]==0x89&&bytes[1]==0x50&&bytes[2]==0x4e&&bytes[3]==0x47&&bytes[4]==0x0d&&bytes[5]==0x0a&&bytes[6]==0x1a&&bytes[7]==0x0a,
    'image/webp'=>bytes.length>=12&&String.fromCharCodes(bytes.sublist(0,4))=='RIFF'&&String.fromCharCodes(bytes.sublist(8,12))=='WEBP',
    _=>false,
  };
}
