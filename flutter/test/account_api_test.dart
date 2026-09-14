import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume/services/api.dart';

LumeSession adminSession()=>LumeSession()
  ..token='signed-admin-session'
  ..profileId='admin-profile'
  ..role='admin'
  ..expiresAt=DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch;

void main(){
  test('registration sends the four approved fields without e-mail',() async {
    final client=MockClient((request) async {
      expect(request.method,'POST');
      expect(request.url.toString(),'https://lume.example/v1/auth/register');
      expect(request.headers['authorization'],isNull);
      final body=Map<String,dynamic>.from(jsonDecode(request.body) as Map);
      expect(body,{
        'fullName':'Ana Souza',
        'username':'ana.souza',
        'password':'senha-forte',
        'className':'2º A',
      });
      expect(body.containsKey('email'),isFalse);
      return http.Response('{"ok":true,"profileId":"student-1","activeCount":2,"maxUsers":91}',201);
    });
    final api=LumeApi(Uri.parse('https://lume.example'),client:client);
    final response=await api.register(
      fullName:'Ana Souza',
      username:'ana.souza',
      password:'senha-forte',
      className:'2º A',
    );
    expect(response['maxUsers'],91);
    api.dispose();
  });

  test('admin list and status change are authenticated',() async {
    var requestNumber=0;
    final client=MockClient((request) async {
      requestNumber++;
      expect(request.headers['authorization'],'Bearer signed-admin-session');
      if(requestNumber==1){
        expect(request.method,'GET');
        expect(request.url.path,'/v1/admin/users');
        return http.Response('{"activeCount":2,"maxUsers":91,"users":[]}',200);
      }
      expect(request.method,'PATCH');
      expect(request.url.path,'/v1/admin/users/ana.souza');
      expect(jsonDecode(request.body),{'active':false});
      return http.Response('{"ok":true,"username":"ana.souza","active":false}',200);
    });
    final api=LumeApi(Uri.parse('https://lume.example'),client:client,session:adminSession());
    expect((await api.adminUsers())['maxUsers'],91);
    expect((await api.setUserActive('ana.souza',false))['active'],isFalse);
    expect(requestNumber,2);
    api.dispose();
  });
}
