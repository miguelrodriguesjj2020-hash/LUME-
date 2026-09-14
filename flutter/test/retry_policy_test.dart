import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/api.dart';
import 'package:lume/services/retry_policy.dart';

void main(){
  test('transient HTTP statuses are retryable but auth is not',(){
    final p=RetryPolicy(maxAttempts:3);
    expect(p.isTransient(const ApiException('sync',429)),isTrue);
    expect(p.isTransient(const ApiException('sync',503)),isTrue);
    expect(p.isTransient(const ApiException('sync',403)),isFalse);
    expect(p.isTransient(const SessionExpiredException('sync')),isFalse);
  });

  test('backoff is bounded',(){
    final p=RetryPolicy(baseDelay:const Duration(milliseconds:100),maxDelay:const Duration(seconds:2));
    for(var i=0;i<20;i++){
      expect(p.delayFor(i).inMilliseconds,lessThanOrEqualTo(2500)); // 2s + <=25% jitter
      expect(p.delayFor(i).inMilliseconds,greaterThanOrEqualTo(100));
    }
  });
}
