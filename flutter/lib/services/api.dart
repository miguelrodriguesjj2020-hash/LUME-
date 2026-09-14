import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SessionExpiredException implements Exception {
  final String operation;
  const SessionExpiredException(this.operation);
  @override String toString() => 'SessionExpiredException($operation)';
}

class ApiException implements Exception {
  final String operation;
  final int statusCode;
  final String? body;
  final Duration? retryAfter;
  const ApiException(this.operation,this.statusCode,[this.body,this.retryAfter]);
  @override String toString()=> 'ApiException($operation, $statusCode)';
}

enum SessionEventType { authenticated, expired, cleared }

class SessionEvent {
  final SessionEventType type;
  final String? profileId;
  final String? reason;
  const SessionEvent(this.type,{this.profileId,this.reason});
}

class LumeSession {
  String? token;
  String? profileId;
  String? role;
  int? expiresAt;

  bool get authenticated => token!=null && token!.isNotEmpty && !expired;
  bool get expired => expiresAt!=null && expiresAt!<=DateTime.now().millisecondsSinceEpoch;

  LumeSession copy()=>LumeSession()
    ..token=token
    ..profileId=profileId
    ..role=role
    ..expiresAt=expiresAt;

  void clear(){token=null;profileId=null;role=null;expiresAt=null;}
}

class LumeApi {
  final Uri base;
  final http.Client client;
  final LumeSession session;
  final _sessionEvents=StreamController<SessionEvent>.broadcast();
  bool _expiredEventSent=false;

  LumeApi(this.base,{http.Client? client,LumeSession? session})
      :client=client??http.Client(),session=session??LumeSession();

  Stream<SessionEvent> get sessionEvents=>_sessionEvents.stream;
  Uri _u(String p,[Map<String,String>? q])=>base.resolve(p).replace(queryParameters:q);

  Map<String,String> _headers([Map<String,String> extra=const{}]) {
    if(session.expired){_expire('local-expiry');}
    return {if(session.authenticated)'authorization':'Bearer ${session.token}',...extra};
  }

  void _expire(String reason){
    final profile=session.profileId;
    session.clear();
    if(!_expiredEventSent){
      _expiredEventSent=true;
      _sessionEvents.add(SessionEvent(SessionEventType.expired,profileId:profile,reason:reason));
    }
  }

  Future<http.Response> _guarded(String operation,Future<http.Response> Function() call) async {
    if(session.expired){
      _expire('local-expiry');
      throw SessionExpiredException(operation);
    }
    final r=await call();
    if(r.statusCode==401){
      _expire('http-401');
      throw SessionExpiredException(operation);
    }
    return r;
  }

  ApiException _apiError(String operation,http.Response r){
    Duration? retryAfter;
    final raw=r.headers['retry-after'];
    final seconds=raw==null?null:int.tryParse(raw.trim());
    if(seconds!=null && seconds>=0)retryAfter=Duration(seconds:seconds);
    return ApiException(operation,r.statusCode,r.body,retryAfter);
  }

  Future<Map<String,dynamic>> login(String username,String password) async {
    final r=await client.post(_u('/v1/auth/login'),headers:{'content-type':'application/json'},body:jsonEncode({'username':username,'password':password}));
    if(r.statusCode!=200)throw _apiError('login',r);
    final j=Map<String,dynamic>.from(jsonDecode(r.body));
    session.token=j['token'] as String?;
    session.profileId=j['profileId'] as String?;
    session.role=j['role'] as String?;
    session.expiresAt=(j['expiresAt'] as num?)?.toInt();
    _expiredEventSent=false;
    _sessionEvents.add(SessionEvent(SessionEventType.authenticated,profileId:session.profileId));
    return j;
  }

  Future<Map<String,dynamic>> register({
    required String fullName,
    required String username,
    required String password,
    required String className,
  }) async {
    final r=await client.post(
      _u('/v1/auth/register'),
      headers:{'content-type':'application/json'},
      body:jsonEncode({
        'fullName':fullName,
        'username':username,
        'password':password,
        'className':className,
      }),
    );
    if(r.statusCode!=201)throw _apiError('register',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  Future<Map<String,dynamic>> adminUsers() async {
    final r=await _guarded('adminUsers',()=>client.get(_u('/v1/admin/users'),headers:_headers()));
    if(r.statusCode!=200)throw _apiError('adminUsers',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  Future<Map<String,dynamic>> setUserActive(String username,bool active) async {
    final r=await _guarded('adminUserStatus',()=>client.patch(
      _u('/v1/admin/users/${Uri.encodeComponent(username)}'),
      headers:_headers({'content-type':'application/json'}),
      body:jsonEncode({'active':active}),
    ));
    if(r.statusCode!=200)throw _apiError('adminUserStatus',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  Future<void> logout() async {
    final profile=session.profileId;
    session.clear();
    _expiredEventSent=false;
    _sessionEvents.add(SessionEvent(SessionEventType.cleared,profileId:profile));
  }

  Future<bool> health() async {
    try {
      final r=await client.get(_u('/v1/health')).timeout(const Duration(seconds:5));
      if(r.statusCode!=200)return false;
      final j=jsonDecode(r.body);
      return j is Map && j['ok']==true && j['service']=='lume';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String,dynamic>?> bootstrap(int revision) async {
    final r=await _guarded('bootstrap',()=>client.get(_u('/v1/bootstrap',{'since':'$revision'}),headers:_headers()));
    if(r.statusCode==304)return null;
    if(r.statusCode!=200)throw _apiError('bootstrap',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  Future<Map<String,dynamic>> media(String id) async {
    final r=await _guarded('media',()=>client.get(_u('/v1/media/$id'),headers:_headers()));
    if(r.statusCode!=200)throw _apiError('media',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  Future<Map<String,dynamic>> cover(String workId) async {
    final r=await _guarded('cover',()=>client.get(_u('/v1/covers/${Uri.encodeComponent(workId)}'),headers:_headers()));
    if(r.statusCode!=200)throw _apiError('cover',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  Future<Map<String,dynamic>> sync(String profile,String cursor,List<Map<String,dynamic>> ops) async {
    final r=await _guarded('sync',()=>client.post(_u('/v1/profiles/$profile/sync'),headers:_headers({'content-type':'application/json'}),body:jsonEncode({'cursor':cursor,'ops':ops})));
    if(r.statusCode!=200)throw _apiError('sync',r);
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  void dispose(){
    client.close();
    _sessionEvents.close();
  }
}
