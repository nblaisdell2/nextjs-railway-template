# Deploy the current folder to Railway right now, without waiting for a push
# (PowerShell).
#   npm run railway:deploy     (or: .\scripts\railway-deploy.ps1)
#
# Uploads this directory (respecting .gitignore), builds the Dockerfile on
# Railway, runs the pre-deploy migrations, and swaps traffic over once
# /api/health passes. Uncommitted changes ARE included, so this is handy for a
# quick check; the next push to main replaces it with what's in git.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/common.ps1")
Set-Location $Root
$total = 3

Write-Step 1 $total "Checking Railway CLI + linked project"
Assert-RailwayCli
Assert-RailwayLogin
Assert-RailwayLinked

Write-Step 2 $total "railway up (build + deploy '$WebService')"
railway up --service $WebService --ci
if ($LASTEXITCODE -ne 0) { throw "railway up failed. Build logs: 'railway logs --service $WebService --build'." }

Write-Step 3 $total "Live"
$domain = Get-RailwayDomain
$customDomain = Get-RailwayConst "CUSTOM_DOMAIN"
if ($domain)       { Write-Host "Deployed:  https://$domain" -ForegroundColor Green }
if ($customDomain) { Write-Host "Custom domain:  https://$customDomain" -ForegroundColor Green }
if (-not $domain -and -not $customDomain) {
    Write-Host "Deployed, but the service has no public domain yet. Run 'npm run railway:domain'." -ForegroundColor Yellow
}
Write-Host "(--ci returns once the build finishes; the new version takes traffic when /api/health passes. Watch it: 'railway logs --service $WebService'.)"
