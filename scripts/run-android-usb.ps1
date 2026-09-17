param([string]$DeviceId)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'adb is required. Add Android SDK platform-tools to PATH.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter is required. Add Flutter bin to PATH.'
}
if (-not $DeviceId) {
    $devices = @(adb devices | Select-String '^([^\s]+)\s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if ($devices.Count -ne 1) {
        throw 'Connect and authorize one Android device, or pass -DeviceId SERIAL.'
    }
    $DeviceId = $devices[0]
}
try {
    $response = Invoke-RestMethod 'http://127.0.0.1:8000/' -TimeoutSec 10
    if ($response.service -ne 'sahlha') { throw 'Unexpected service on port 8000.' }
} catch {
    throw 'Start the backend first: python -m uvicorn sahlha.app.main:app --reload --port 8000'
}
adb -s $DeviceId reverse tcp:8000 tcp:8000
if ($LASTEXITCODE -ne 0) { throw 'Could not configure Android USB port forwarding.' }
Push-Location (Join-Path $PSScriptRoot '../mobile')
try {
    flutter run -d $DeviceId --dart-define=API_BASE_URL=http://127.0.0.1:8000
    if ($LASTEXITCODE -ne 0) { throw 'Flutter failed to launch.' }
} finally {
    Pop-Location
}
