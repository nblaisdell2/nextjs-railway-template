# Apply migrations to the LIVE Railway database by hand (PowerShell).
#   npm run railway:migrate     (or: .\scripts\railway-migrate.ps1)
#
# You rarely need this: every deploy already runs `npm run migrate` as its
# pre-deploy command. It's the escape hatch for re-running migrations without
# a deploy.
#
# It runs `npm run migrate` INSIDE the running web container over `railway ssh`,
# so it uses the DATABASE_URL Railway injects there (the private-network URL)
# and never your local .env. (`railway run` would run on your laptop, where
# postgres.railway.internal doesn't resolve.) The container holds the migration
# files of the version that's deployed, so push new migrations first.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/common.ps1")
Set-Location $Root
$total = 2

Write-Step 1 $total "Checking Railway CLI + linked project"
Assert-RailwayCli
Assert-RailwayLogin
Assert-RailwayLinked

Write-Step 2 $total "npm run migrate inside the '$WebService' container"
railway ssh --service $WebService -- sh -c "cd /app && npm run migrate"
if ($LASTEXITCODE -ne 0) { throw "Migration failed (see output above). Logs: 'railway logs --service $WebService'." }

Write-Host "`nMigrations applied to the Railway database." -ForegroundColor Green
