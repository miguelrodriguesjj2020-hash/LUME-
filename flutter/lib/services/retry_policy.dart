import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'api.dart';

class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;
  RetryPolicy({this.maxAttempts=5,this.baseDelay=const Duration(milliseconds:500),this.maxDelay=const Duration(seconds:20),Random? random}) : assert(maxAttempts>0), _random=random??Random();

  bool isTransient(Object error)=>
      error is TimeoutException ||
      error is http.ClientException ||
      (error is ApiException && (error.statusCode==408 || error.statusCode==425 || error.statusCode==429 || error.statusCode>=500));

  Duration delayFor(int attempt,{Duration? retryAfter}) {
    if(retryAfter!=null && retryAfter<=maxDelay)return retryAfter;
    final exponent=attempt<0?0:(attempt>20?20:attempt);
    final factor=1 << exponent;
    final raw=min(maxDelay.inMilliseconds,baseDelay.inMilliseconds*factor).toInt();
    final jitter=(raw*0.25*_random.nextDouble()).round();
    return Duration(milliseconds:raw+jitter);
  }

  Future<T> run<T>(Future<T> Function() operation,{Duration? retryAfter}) async {
    Object? last;
    for(var attempt=0;attempt<maxAttempts;attempt++){
      try{return await operation();}catch(e){
        last=e;
        if(e is SessionExpiredException || !isTransient(e) || attempt==maxAttempts-1)rethrow;
        final serverDelay=e is ApiException?e.retryAfter:null;
        await Future<void>.delayed(delayFor(attempt,retryAfter:serverDelay??retryAfter));
      }
    }
    throw last!;
  }
}
