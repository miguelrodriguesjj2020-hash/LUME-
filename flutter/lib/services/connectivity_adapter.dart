import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'network_policy.dart';

/// Thin platform adapter. It reports transport availability only; callers must
/// still handle real HTTP failures/timeouts because Wi-Fi != Internet access.
class ConnectivityAdapter {
  final Connectivity connectivity;
  ConnectivityAdapter({Connectivity? connectivity}) : connectivity=connectivity ?? Connectivity();

  Future<NetworkClass> current() async => _map(await connectivity.checkConnectivity());

  Stream<NetworkClass> get changes => connectivity.onConnectivityChanged.map(_map).distinct();

  static NetworkClass _map(List<ConnectivityResult> results){
    if(results.isEmpty || results.every((x)=>x==ConnectivityResult.none)) return NetworkClass.offline;
    if(results.contains(ConnectivityResult.ethernet)) return NetworkClass.ethernet;
    if(results.contains(ConnectivityResult.wifi)) return NetworkClass.wifi;
    if(results.contains(ConnectivityResult.mobile)) return NetworkClass.cellular;
    return NetworkClass.other;
  }
}
