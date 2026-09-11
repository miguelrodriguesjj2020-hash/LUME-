import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/api.dart';
import 'package:lume/services/session_vault.dart';

class FakeSessionSecretStore implements SessionSecretStore {
  final values=<String,String>{};
  int deletes=0;

  @override
  Future<String?> read(String key) async=>values[key];

  @override
  Future<void> write(String key,String value) async{values[key]=value;}

  @override
  Future<void> delete(String key) async{values.remove(key);deletes++;}
}

class BlockingWriteSessionSecretStore extends FakeSessionSecretStore {
  final writeStarted=Completer<void>();
  final releaseWrite=Completer<void>();

  @override
  Future<void> write(String key,String value) async{
    if(!writeStarted.isCompleted)writeStarted.complete();
    await releaseWrite.future;
    await super.write(key,value);
  }
}

LumeSession validSession()=>LumeSession()
  ..token='token-123'
  ..profileId='student-7'
  ..role='consumer'
  ..expiresAt=DateTime.now().add(const Duration(hours:1)).millisecondsSinceEpoch;

void main(){
  test('secure session vault round-trips token and metadata without password',() async{
    final secrets=FakeSessionSecretStore();
    final vault=SecureSessionVault(secrets);
    final original=validSession();
    await vault.save(original);
    expect(secrets.values.length,1);
    final json=Map<String,dynamic>.from(jsonDecode(secrets.values.values.single));
    expect(json['schema'],1);
    expect(json['token'],'token-123');
    expect(json['profileId'],'student-7');
    expect(json['role'],'consumer');
    expect(json.containsKey('password'),isFalse);
    final restored=await vault.load();
    expect(restored,isNotNull);
    expect(restored!.authenticated,isTrue);
    expect(restored.token,original.token);
    expect(restored.profileId,original.profileId);
    expect(restored.role,original.role);
    expect(restored.expiresAt,original.expiresAt);
  });

  test('expired persisted session is deleted and not restored',() async{
    final secrets=FakeSessionSecretStore();
    final vault=SecureSessionVault(secrets);
    final expired=validSession()..expiresAt=DateTime.now().subtract(const Duration(minutes:1)).millisecondsSinceEpoch;
    secrets.values['session_v1']=jsonEncode({
      'schema':1,
      'token':expired.token,
      'profileId':expired.profileId,
      'role':expired.role,
      'expiresAt':expired.expiresAt,
    });
    expect(await vault.load(),isNull);
    expect(secrets.values,isEmpty);
    expect(secrets.deletes,1);
  });

  test('malformed persisted session fails closed and is deleted',() async{
    final secrets=FakeSessionSecretStore()..values['session_v1']='{"schema":1,"token":7}';
    final vault=SecureSessionVault(secrets);
    expect(await vault.load(),isNull);
    expect(secrets.values,isEmpty);
    expect(secrets.deletes,1);
  });

  test('saving an unauthenticated session clears persisted credentials',() async{
    final secrets=FakeSessionSecretStore()..values['session_v1']='stale';
    final vault=SecureSessionVault(secrets);
    await vault.save(LumeSession());
    expect(secrets.values,isEmpty);
    expect(secrets.deletes,1);
  });

  test('clear ordered after an in-flight save cannot resurrect credentials',() async{
    final secrets=BlockingWriteSessionSecretStore();
    final vault=SecureSessionVault(secrets);
    final saveFuture=vault.save(validSession());
    await secrets.writeStarted.future;
    final clearFuture=vault.clear();
    secrets.releaseWrite.complete();
    await saveFuture;
    await clearFuture;
    expect(secrets.values,isEmpty);
    expect(secrets.deletes,1);
  });

  test('save persists an immutable snapshot even if caller mutates session',() async{
    final secrets=BlockingWriteSessionSecretStore();
    final vault=SecureSessionVault(secrets);
    final session=validSession();
    final expectedExpiry=session.expiresAt;
    final saveFuture=vault.save(session);
    await secrets.writeStarted.future;
    session
      ..token='mutated-token'
      ..profileId='other-profile'
      ..role='admin'
      ..expiresAt=DateTime.now().add(const Duration(days:30)).millisecondsSinceEpoch;
    secrets.releaseWrite.complete();
    await saveFuture;
    final json=Map<String,dynamic>.from(jsonDecode(secrets.values['session_v1']!));
    expect(json['token'],'token-123');
    expect(json['profileId'],'student-7');
    expect(json['role'],'consumer');
    expect(json['expiresAt'],expectedExpiry);
  });
}
