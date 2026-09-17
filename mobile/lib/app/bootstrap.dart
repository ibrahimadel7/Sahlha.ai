import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/auth/auth_controller.dart';

/// Creates the top-level [ProviderContainer] and wires global callbacks
/// (e.g. 401 from Dio -> sign out -> router sends the user to login).
Future<ProviderContainer> bootstrap() async {
  final container = ProviderContainer();
  final api = container.read(apiClientProvider);
  api.onUnauthorized = () {
    container.read(authControllerProvider.notifier).handleUnauthorized();
  };
  // Warm the auth state so the router can redirect correctly on first frame.
  await container.read(authControllerProvider.future);
  return container;
}
