import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

/// Storage boundary for authenticated session state.
abstract interface class SessionVault {
  Future<LumeSession?> load();
  Future<void> save(LumeSession session);
  Future<void> clear();
}

/// Minimal string secret-store boundary so vault behavior can be unit tested
/// without invoking a platform MethodChannel.
abstract interface class SessionSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key,String value);
  Future<void> delete(String key);
}

class FlutterSecureSessionStore implements SessionSecretStore {
  final FlutterSecureStorage storage;

  FlutterSecureSessionStore({FlutterSecureStorage? storage})
      : storage=storage??const FlutterSecureStorage(
          aOptions:AndroidOptions(
            storageNamespace:'lume_auth_v1',
            resetOnError:true,
            migrateOnAlgorithmChange:true,
          ),
        );

  @override
  Future<String?> read(String key)=>storage.read(key:key);

  @override
  Future<void> write(String key,String value)=>storage.write(key:key,value:value);

  @override
  Future<void> delete(String key)=>storage.delete(key:key);
}

class SecureSessionVault implements SessionVault {
  static const _key='session_v1';
  static const _schema=1;
  final SessionSecretStore secrets;
  Future<void> _tail=Future<void>.value();

  SecureSessionVault(this.secrets);

  Future<void> _enqueue(Future<void> Function() operation){
    final next=_tail.then((_)=>operation());
    _tail=next.catchError((_){ });
    return next;
  }

  @override
  Future<LumeSession?> load() async {
    await _tail;
    try{
      final raw=await secrets.read(_key);
      if(raw==null || raw.isEmpty)return null;
      final decoded=jsonDecode(raw);
      if(decoded is! Map)throw const FormatException('session is not an object');
      final j=Map<String,dynamic>.from(decoded);
      if(j['schema']!=_schema)throw const FormatException('unsupported session schema');
      final token=j['token'];
      final profileId=j['profileId'];
      final role=j['role'];
      final expiresAt=j['expiresAt'];
      if(token is! String || token.isEmpty ||
          profileId is! String || profileId.isEmpty ||
          role is! String || role.isEmpty ||
          expiresAt is! int){
        throw const FormatException('invalid session fields');
      }
      final session=LumeSession()
        ..token=token
        ..profileId=profileId
        ..role=role
        ..expiresAt=expiresAt;
      if(!session.authenticated){
        await clear();
        return null;
      }
      return session;
    }catch(_){
      try{await clear();}catch(_){}
      return null;
    }
  }

  @override
  Future<void> save(LumeSession session) {
    final token=session.token;
    final profileId=session.profileId;
    final role=session.role;
    final expiresAt=session.expiresAt;
    final authenticated=session.authenticated;
    return _enqueue(() async {
      if(!authenticated || token==null || profileId==null || role==null || expiresAt==null){
        await secrets.delete(_key);
        return;
      }
      await secrets.write(_key,jsonEncode({
        'schema':_schema,
        'token':token,
        'profileId':profileId,
        'role':role,
        'expiresAt':expiresAt,
      }));
    });
  }

  @override
  Future<void> clear()=>_enqueue(()=>secrets.delete(_key));
}

class MemorySessionVault implements SessionVault {
  LumeSession? _session;

  @override
  Future<LumeSession?> load() async => _session?.copy();

  @override
  Future<void> save(LumeSession session) async {
    _session = session.copy();
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
