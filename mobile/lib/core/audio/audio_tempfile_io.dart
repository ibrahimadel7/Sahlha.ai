import 'dart:io' show File;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Write downloaded WAV bytes to a single reused temp slot and return its
/// path. Only one explanation plays at a time, so one file suffices and no
/// temp files accumulate across taps.
Future<String> writeTempAudio(Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/read_aloud_current.wav');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
