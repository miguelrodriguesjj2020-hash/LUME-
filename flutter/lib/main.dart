import 'dart:async';
import 'package:flutter/material.dart';
import 'services/api.dart';
import 'services/app_services.dart';
import 'services/session_vault.dart';
import 'services/sync.dart';
import 'services/network_policy.dart';
import 'ui/catalog_page.dart';
import 'ui/login_page.dart';

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
  final SessionVault sessionVault=MemorySessionVault();
  late final LumeApi api=LumeApi(widget.apiBase);
  StreamSubscription<SessionEvent>? sessionSub;
  StreamSubscription<NetworkClass>? connectivitySub;
  NetworkClass? lastNetwork;
  AppServices? services;
  bool creating=false;
  String? loginNotice;

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sessionSub=api.sessionEvents.listen(_onSessionEvent);
  }

  Future<void> _onSessionEvent(SessionEvent event) async {
    if(event.type==SessionEventType.authenticated){
      await sessionVault.save(api.session);
      return;
    }
    await sessionVault.clear();
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
      services!.sync.run(services!.profileId,mode:SyncRunMode.foreground).catchError((_){return null;});
      services!.revalidateRecentMedia().catchError((_){return null;});
    }
  }

  @override
  Widget build(BuildContext context)=>MaterialApp(
    navigatorKey:navigatorKey,
    debugShowCheckedModeBanner:false,
    title:'LUME',
    theme:ThemeData(useMaterial3:true),
    home:services==null
      ? LoginPage(api:api,onAuthenticated:authenticated,notice:loginNotice)
      : CatalogPage(services:services!),
  );
}
