import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/api/api_client.dart';

void main() {
  test(
    'API client retains authentication while no screen watches it',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(apiClientProvider, (_, _) {});
      final client = subscription.read();
      client.setToken('test-session-token');
      var unauthorizedCalled = false;
      client.onUnauthorized = () => unauthorizedCalled = true;

      subscription.close();
      await container.pump();

      final restored = container.read(apiClientProvider);
      expect(identical(restored, client), isTrue);
      expect(restored.token, 'test-session-token');
      restored.onUnauthorized?.call();
      expect(unauthorizedCalled, isTrue);
    },
  );
}
