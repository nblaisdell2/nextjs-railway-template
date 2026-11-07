# Apply migrations to the LIVE Railway database by hand (PowerShell).
#   npm run railway:migrate              (or: .\scripts\railway-migrate.ps1 [-Ssh])
#
# You rarely need this: every deploy already runs `npm run migrate` as its
# pre-deploy command. It's the escape hatch for re-running migrations without
# pushing new code. It always uses the DATABASE_URL Railway injects into the
# web service, never your local .env.
#
# Default: redeploys the current version of `web` (`railway redeploy`), which
# re-runs the pre-deploy `npm run migrate` and swaps traffic once /api/health
# passes. No SSH keys needed, and the database stays private.
#
# -Ssh: runs `npm run migrate` inside the running container over `railway ssh`
# instead (no restart, output right here). Needs an SSH key on this machine
# (`ssh-keygen -t ed25519`).
#
# Either way the migrations are the ones in the DEPLOYED image, so push new
# migration files first. (`railway run npm run migrate` won't work: it runs on
# your laptop, where postgres.railway.internal doesn't resolve.)

[CmdletBinding()]
param(
    [switch]$Ssh
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/common.ps1")
Set-Location $Root
$total = 2

Write-Step 1 $total "Checking Railway CLI + linked project"
Assert-RailwayCli
Assert-RailwayLogin
Assert-RailwayLinked

if ($Ssh) {
    Write-Step 2 $total "npm run migrate inside the '$WebService' container (railway ssh)"
    railway ssh --service $WebService -- sh -c "cd /app && npm run migrate"
    if ($LASTEXITCODE -ne 0) { throw "Migration over SSH failed (see output above). Without an SSH key, run this without -Ssh." }
} else {
    Write-Step 2 $total "Redeploying '$WebService' (re-runs the pre-deploy migrations)"
    $before = Get-LatestDeployment
    if (-not $before) { throw "'$WebService' has no deployment yet. Run 'npm run railway:setup' first." }
    railway redeploy --service $WebService --yes
    if ($LASTEXITCODE -ne 0) { throw "railway redeploy failed" }
    Wait-RailwayDeploy -AfterId ([string]$before.id) -StartMinutes 2 -NoStartHint "Check the dashboard ('railway open')."
    Write-Host "`nMigration output (from the pre-deploy step):"
    railway logs --service $WebService --lines 200 2>$null |
        Select-String -Pattern '^(\+ apply|= skip|Done\.|Failed on)' |
        ForEach-Object { "  $($_.Line)" }
}

Write-Host "`nMigrations applied to the Railway database." -ForegroundColor Green
