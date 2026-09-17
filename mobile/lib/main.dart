import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = await bootstrap();
  runApp(
    DevicePreview(
      enabled: kDebugMode && kIsWeb,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const SahlhaApp(),
      ),
    ),
  );
}
