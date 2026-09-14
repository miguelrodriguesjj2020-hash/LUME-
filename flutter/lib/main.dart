import 'dart:async';
import 'package:flutter/material.dart';
import 'services/api.dart';
import 'services/app_services.dart';
import 'services/session_vault.dart';
import 'services/sync.dart';
import 'services/network_policy.dart';
import 'ui/catalog_page.dart';
import 'ui/login_page.dart';
import 'ui/lume_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const rawBase = String.fromEnvironment('LUME_API_BASE', defaultValue: 'https://lume.invalid');
  runApp(LumeBootstrap(apiBase: Uri.parse(rawBase)));
}

class LumeBootstrap extends StatefulWidget {
  final Uri apiBase;
  const LumeBootstrap({super.key,required this.apiBase});
  @override State<LumeBootstrap> createState()=>_LumeBootstrapState();
}

class _LumeBootstrapState extends State<LumeBootstrap> with WidgetsBindingObserver {
  final navigatorKey=GlobalKey<NavigatorState>();
  late final SessionVault sessionVault=SecureSessionVault(FlutterSecureSessionStore());
  late final LumeApi api=LumeApi(widget.apiBase);
  StreamSubscription<SessionEvent>? sessionSub;
  StreamSubscription<NetworkClass>? connectivitySub;
  NetworkClass? lastNetwork;
  AppServices? services;
  bool creating=false;
  bool restoringSession=true;
  String? loginNotice;

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sessionSub=api.sessionEvents.listen(_onSessionEvent);
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    try{
      final restored=await sessionVault.load();
      if(restored!=null && restored.authenticated){
        api.session
          ..token=restored.token
          ..profileId=restored.profileId
          ..role=restored.role
          ..expiresAt=restored.expiresAt;
        await authenticated();
      }
    }catch(_){
      try{await sessionVault.clear();}catch(_){}
    }finally{
      if(mounted)setState(()=>restoringSession=false);
    }
  }

  Future<void> _onSessionEvent(SessionEvent event) async {
    if(event.type==SessionEventType.authenticated){
      try{await sessionVault.save(api.session);}catch(_){}
      return;
    }
    try{await sessionVault.clear();}catch(_){}
    await connectivitySub?.cancel();
    connectivitySub=null;
    lastNetwork=null;
    services?.reconnect.dispose();
    services?.offlineDownloads.dispose();
    if(!mounted)return;
    setState((){
      services=null;
      creating=false;
      loginNotice=event.type==SessionEventType.expired
          ? 'Sua sessão expirou. Entre novamente; sua leitura e downloads locais foram preservados.'
          : null;
    });
    // Force the authentication boundary even when expiry happened from a
    // reader/download route above the app home.
    navigatorKey.currentState?.popUntil((route)=>route.isFirst);
  }

  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    sessionSub?.cancel();
    connectivitySub?.cancel();
    services?.reconnect.dispose();
    services?.offlineDownloads.dispose();
    api.dispose();
    super.dispose();
  }

  Future<void> authenticated() async {
    if(creating)return;
    setState((){creating=true;loginNotice=null;});
    try{
      final s=await AppServices.create(
        apiBase:widget.apiBase,
        existingApi:api,
        profileId:api.session.profileId,
      );
      if(!mounted)return;
      await connectivitySub?.cancel();
      lastNetwork=await s.connectivity.current();
      s.reconnect.seed(lastNetwork!);
      connectivitySub=s.connectivity.changes.listen((network){
        lastNetwork=network;
        s.reconnect.onNetwork(network);
      });
      setState((){services=s;creating=false;});
    }catch(_){
      if(!mounted)return;
      setState((){creating=false;loginNotice='Não foi possível inicializar a biblioteca local.';});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed && services!=null){
      services!.offlineDownloads.reconcile();
      // SessionExpiredException is surfaced by LumeApi through sessionEvents;
      // local state remains in SQLite if the network/session is unavailable.
      unawaited(() async {
        try { await services!.sync.run(services!.profileId,mode:SyncRunMode.foreground); } catch (_) {}
      }());
      // Advisory stale-while-revalidate: never blocks local reading or demotes READY assets.
      unawaited(() async {
        try { await services!.revalidateRecentMedia(); } catch (_) {}
      }());
    }
  }

  @override
  Widget build(BuildContext context)=>MaterialApp(
    navigatorKey:navigatorKey,
    debugShowCheckedModeBanner:false,
    title:'LUME',
    theme:LumeTheme.light(),
    home:restoringSession
      ? const Scaffold(body:Center(child:CircularProgressIndicator()))
      : services==null
        ? LoginPage(api:api,onAuthenticated:authenticated,notice:loginNotice)
        : CatalogPage(services:services!),
  );
}
