import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/models/catalog.dart';
import 'package:lume/services/api.dart';
import 'package:lume/services/cover_cache.dart';

void main(){
  final bytes=<int>[0xff,0xd8,0xff,0xd9];
  final hash=sha256.convert(bytes).toString();
  Work work()=>Work(id:'manga-test',title:'Teste',type:'manga',sources:const[],editions:const[],cover:CoverAsset(sourceFileId:'private',fileName:'cover.jpg',mimeType:'image/jpeg',sha256:hash,byteSize:bytes.length));

  test('verified cover is persisted and cache avoids a second request',() async {
    var calls=0;
    final client=MockClient((request) async {
      calls++;
      if(request.url.path.startsWith('/v1/covers/'))return http.Response('{"url":"https://media.example/cover","byteSize":4,"mimeType":"image/jpeg","sha256":"$hash"}',200);
      return http.Response.bytes(bytes,200,headers:{'content-type':'image/jpeg'});
    });
    final session=LumeSession()..token='token'..profileId='p'..role='consumer'..expiresAt=DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch;
    final api=LumeApi(Uri.parse('https://lume.example'),client:client,session:session);
    final directory=await Directory.systemTemp.createTemp('lume-cover-');
    final cache=CoverCache(api:api,directory:directory);
    final first=await cache.resolve(work());final second=await cache.resolve(work());
    expect(first!.path,second!.path);expect(calls,2);expect(await first.readAsBytes(),bytes);
    await directory.delete(recursive:true);api.dispose();
  });

  test('hash substitution is rejected before persistence',() async {
    final wrong=''.padLeft(64,'0');
    final client=MockClient((request) async {
      if(request.url.path.startsWith('/v1/covers/'))return http.Response('{"url":"https://media.example/cover","byteSize":4,"mimeType":"image/jpeg","sha256":"$wrong"}',200);
      return http.Response.bytes(bytes,200);
    });
    final session=LumeSession()..token='token'..profileId='p'..role='consumer'..expiresAt=DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch;
    final api=LumeApi(Uri.parse('https://lume.example'),client:client,session:session);
    final directory=await Directory.systemTemp.createTemp('lume-cover-');
    await expectLater(CoverCache(api:api,directory:directory).resolve(work()),throwsA(isA<CoverCacheException>()));
    expect(directory.listSync(),isEmpty);await directory.delete(recursive:true);api.dispose();
  });
}
