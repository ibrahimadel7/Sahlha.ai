# Quick public URL for the local backend — no Cloudflare login needed.
# Keeps SQLite + data/ + .env exactly as local dev. Ideal for mobile testing.
#
# Usage (two terminals):
#   Terminal 1: python -m uvicorn sahlha.app.main:app --host 127.0.0.1 --port 8000
#   Terminal 2: powershell -ExecutionPolicy Bypass -File scripts/cloudflare-tunnel-quick.ps1
#
# Then set the Flutter app to the printed https://*.trycloudflare.com URL:
#   flutter run --dart-define API_BASE_URL=<that-url>
param(
  [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

Write-Output "Checking backend on http://127.0.0.1:$Port/health ..."
try {
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
  Write-Output ($health | ConvertTo-Json -Compress)
} catch {
  Write-Output "Backend is not responding. Start it first:"
  Write-Output "  python -m uvicorn sahlha.app.main:app --host 127.0.0.1 --port $Port"
  exit 1
}

Write-Output ""
Write-Output "Opening Cloudflare quick tunnel (no login required) ..."
Write-Output "Leave this running. Copy the https://*.trycloudflare.com URL into API_BASE_URL."
& cloudflared tunnel --url "http://127.0.0.1:$Port"
