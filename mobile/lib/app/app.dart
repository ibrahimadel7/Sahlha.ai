import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/sahlha_theme.dart';
import 'router.dart';

class SahlhaApp extends ConsumerWidget {
  const SahlhaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Sahlha',
      debugShowCheckedModeBanner: false,
      theme: SahlhaTheme.light(),
      routerConfig: router,
      locale: kIsWeb ? DevicePreview.locale(context) : null,
      builder: kIsWeb ? DevicePreview.appBuilder : null,
    );
  }
}
