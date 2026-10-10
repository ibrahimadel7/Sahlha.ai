# Full deploy: FastAPI Docker image -> Cloudflare Containers.
# Prerequisites: `wrangler login` (browser) + Docker Desktop running.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/cloudflare-deploy.ps1
#
# Secrets (run once, names must match your .env keys you want in production):
#   cd workers/backend-proxy
#   wrangler secret put GROQ_API_KEY
#   wrangler secret put JWT_SECRET
#   wrangler secret put PEXELS_API_KEY
#   wrangler secret put OPENROUTER_API_KEY
param()

$ErrorActionPreference = "Stop"
$ProxyDir = Join-Path $PSScriptRoot ".." "workers" "backend-proxy"

Write-Output "== 1/4 Docker daemon =="
try {
  docker info --format '{{.ServerVersion}}' | Write-Output
} catch {
  Write-Output "Docker Desktop is not running. Starting it now ..."
  Start-Process -FilePath "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  Write-Output "Wait ~60s for the whale icon to stop animating, then re-run this script."
  exit 1
}

Write-Output "== 2/4 Wrangler auth =="
wrangler whoami
if ($LASTEXITCODE -ne 0) {
  Write-Output "Not logged in. Running `wrangler login` ..."
  wrangler login
}

Write-Output "== 3/4 Install proxy deps =="
Push-Location $ProxyDir
try {
  npm install
  Write-Output "== 4/4 Deploy (builds Dockerfile + pushes to Cloudflare) =="
  wrangler deploy
} finally {
  Pop-Location
}

Write-Output ""
Write-Output "Done. Test with:"
Write-Output "  curl https://<your-worker>.workers.dev/edge-health"
Write-Output "  curl https://<your-worker>.workers.dev/health"
Write-Output ""
Write-Output "NOTE: container disk is ephemeral — SQLite/data/ resets on eviction."
Write-Output "For production, move DATABASE_URL to Postgres and uploads to R2."
