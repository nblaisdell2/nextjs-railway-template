# Tear down EVERYTHING this project created on Railway (PowerShell).
#   npm run railway:destroy             (or: .\scripts\railway-destroy.ps1 [-Yes])
#
# Deletes the whole Railway project: the web service, the Postgres database
# AND ALL ITS DATA, domains and variables. Your code on GitHub and your local
# files are untouched. Take a backup first if you want to keep the data.
#   -Yes   skip the "type the project name" confirmation

[CmdletBinding()]
param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/common.ps1")
Set-Location $Root
$total = 3

Write-Step 1 $total "Finding the linked Railway project"
Assert-RailwayCli
Assert-RailwayLogin
Assert-RailwayLinked
$status = (railway status --json | Out-String) | ConvertFrom-Json
$projectId   = [string]$status.id
$projectName = [string]$status.name
if (-not $projectId -or -not $projectName) { throw "Could not read the linked project's id/name from 'railway status --json'." }
$declared = Get-RailwayConst "PROJECT_NAME"
if ($declared -ne $projectName) {
    Write-Host "Note: the linked project is '$projectName' but .railway/railway.ts declares '$declared'." -ForegroundColor Yellow
}

Write-Step 2 $total "Confirm"
Write-Host "This will DELETE the Railway project '$projectName' ($projectId):" -ForegroundColor Yellow
Write-Host "  - service '$WebService' and all its deployments and domains"
Write-Host "  - service '$DbService' (PostgreSQL) and ALL ITS DATA" -ForegroundColor Red
Write-Host "  - every variable in the project"
Write-Host "GitHub and your local files are not touched."
Write-Host ""
Write-Host "Want the data? Backups live inside the project and are deleted with it, so take a"
Write-Host "dump first: pg_dump `"<DATABASE_PUBLIC_URL of $DbService>`" > backup.sql"
Write-Host "(copy the URL from 'railway variables --service $DbService')."
if (-not $Yes) {
    if (-not (Test-Interactive)) { throw "Refusing to delete without confirmation. Re-run interactively or pass -Yes." }
    $answer = Read-Host "Type the project name ('$projectName') to confirm"
    if ($answer -ne $projectName) { Write-Host "Aborted."; exit 1 }
}

Write-Step 3 $total "railway delete"
railway delete --project $projectId --yes
if ($LASTEXITCODE -ne 0) { throw "railway delete failed (accounts with 2FA may need --2fa-code; or delete it in the dashboard)" }
railway unlink *> $null
Write-Host "`nDeletion requested; Railway removes the project shortly. This folder is now unlinked." -ForegroundColor Green
Write-Host "To deploy again later: npm run railway:setup"
