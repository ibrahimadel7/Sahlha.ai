import 'dart:typed_data';

/// Web/other non-IO platforms: temp-file playback is unsupported (callers
/// use a data URI instead). This stub keeps web builds compiling.
Future<String> writeTempAudio(Uint8List bytes) =>
    throw UnsupportedError('temp audio files are not supported here');
