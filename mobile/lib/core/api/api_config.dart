/// Base URL of the Sahlha FastAPI backend.
///
/// Override at run time with:
///   flutter run --dart-define API_BASE_URL=http://127.0.0.1:8000
///
/// Defaults:
/// - Android emulator -> http://10.0.2.2:8000
/// - Physical device over USB -> `adb reverse tcp:8000 tcp:8000`, then
///   run with --dart-define API_BASE_URL=http://127.0.0.1:8000
///   Or run scripts/run-android-usb.ps1 from the repository root.
/// API_BASE_URL is compiled into the app; restart flutter run after changing it.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
