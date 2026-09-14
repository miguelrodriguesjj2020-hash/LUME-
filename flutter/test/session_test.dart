import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/api.dart';
import 'package:lume/services/session_vault.dart';

void main(){
  test('expired session is not authenticated',(){
    final s=LumeSession()
      ..token='t'
      ..profileId='p'
      ..expiresAt=DateTime.now().millisecondsSinceEpoch-1;
    expect(s.expired,isTrue);
    expect(s.authenticated,isFalse);
  });

  test('memory vault copies session instead of aliasing it',() async{
    final vault=MemorySessionVault();
    final s=LumeSession()..token='one'..profileId='p';
    await vault.save(s);
    s.token='two';
    expect((await vault.load())!.token,'one');
    await vault.clear();
    expect(await vault.load(),isNull);
  });
}
