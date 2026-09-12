import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/services/api.dart';
import 'package:lume/ui/admin_catalog_page.dart';

LumeSession session(String role)=>LumeSession()
  ..token='signed-session'
  ..profileId=role=='admin'?'admin-1':'student-1'
  ..role=role
  ..expiresAt=DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch;

void main(){
  test('admin catalog publish sends authenticated full manifest',() async {
    final client=MockClient((request) async {
      expect(request.method,'POST');
      expect(request.url.toString(),'https://lume.example/v1/admin/catalog');
      expect(request.headers['authorization'],'Bearer signed-session');
      final body=jsonDecode(request.body) as Map<String,dynamic>;
      expect(body['revision'],7);
      expect((body['works'] as List).single['id'],'w1');
      return http.Response('{"revision":7}',200,headers:{'content-type':'application/json'});
    });
    final api=LumeApi(Uri.parse('https://lume.example'),client:client,session:session('admin'));
    final revision=await api.publishCatalog({'revision':7,'works':[{'id':'w1'}],'tombstones':[]});
    expect(revision,7);
    api.dispose();
  });

  test('non-admin cannot publish catalog',() async {
    var called=false;
    final client=MockClient((_) async {called=true;return http.Response('{}',500);});
    final api=LumeApi(Uri.parse('https://lume.example'),client:client,session:session('consumer'));
    await expectLater(api.publishCatalog({'revision':2,'works':[],'tombstones':[]}),throwsA(isA<ApiException>().having((e)=>e.statusCode,'statusCode',403)));
    expect(called,false);
    api.dispose();
  });
}
