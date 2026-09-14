import 'dart:async';
import 'api.dart';
import 'network_policy.dart';
import 'sync.dart';

/// Debounces noisy connectivity transitions. A transport transition is only a
/// hint; a LUME protocol probe must succeed before background sync is started.
class ReconnectCoordinator {
  final LumeApi api;
  final SyncCoordinator sync;
  final String profileId;
  final Duration debounce;
  Timer? _timer;
  NetworkClass? _last;
  bool _disposed=false;

  ReconnectCoordinator({required this.api,required this.sync,required this.profileId,this.debounce=const Duration(seconds:2)});

  void seed(NetworkClass network)=>_last=network;

  void onNetwork(NetworkClass network){
    if(_disposed)return;
    final wasOffline=_last==NetworkClass.offline;
    _last=network;
    if(network==NetworkClass.offline){_timer?.cancel();return;}
    if(!wasOffline)return;
    _timer?.cancel();
    _timer=Timer(debounce,() async {
      if(_disposed || _last==NetworkClass.offline)return;
      try{
        if(!await api.health())return; // captive portal / wrong endpoint / no Internet
        await sync.run(profileId,mode:SyncRunMode.background);
      }catch(_){/* HTTP/backoff remains authoritative. */}
    });
  }

  void dispose(){_disposed=true;_timer?.cancel();}
}
