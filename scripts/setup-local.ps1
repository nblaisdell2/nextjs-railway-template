# One-shot local onboarding for a freshly cloned project (PowerShell).
#   npm run setup        (or: .\scripts\setup-local.ps1 [-DbPassword ...] [-DbName test] [-DbPort 5432])
#
# 1) prompt for the local Postgres password (hidden input)
# 2) npm install
# 3) write .env (DATABASE_URL -> local database, default name "test"; DATABASE_SSL=disable)
# 4) create that database if missing, then apply migrations
# 5) personalize from the template (project name = folder, repo = <gh-user>/<folder>)
#
# Prereq for step 4: a local Postgres is running, e.g.
#   docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

[CmdletBinding()]
param(
    [string]$DbPassword,
    [string]$DbName = "test",
    [int]$DbPort = 5432
)

$ErrorActionPreference = "Stop"
$scriptsDir = $PSScriptRoot
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

# --- 1. password ---
Write-Host "==> [1/5] Local Postgres password" -ForegroundColor Cyan
if (-not $DbPassword) {
    $secure = Read-Host "Local Postgres password" -AsSecureString
    $DbPassword = [System.Net.NetworkCredential]::new("", $secure).Password
}
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw "Database password is required." }

# --- 2. npm install ---
Write-Host "`n==> [2/5] npm install" -ForegroundColor Cyan
npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed" }

# --- 3. .env ---
Write-Host "`n==> [3/5] Writing .env (database '$DbName')" -ForegroundColor Cyan
$enc   = [uri]::EscapeDataString($DbPassword)   # URL-safe password
$dbUrl = "postgres://postgres:$enc@localhost:$DbPort/$DbName"
$envExample = Join-Path $root ".env.example"
$envPath    = Join-Path $root ".env"
$content = if (Test-Path $envExample) { Get-Content $envExample -Raw } else { "DATABASE_URL=`nDATABASE_SSL=disable`n" }
# Use a match evaluator so '$' in the password can't be read as a regex group.
if ($content -match '(?m)^DATABASE_URL=') {
    $content = [regex]::Replace($content, '(?m)^DATABASE_URL=.*$', { param($m) "DATABASE_URL=$dbUrl" })
} else {
    $content = "DATABASE_URL=$dbUrl`n" + $content
}
if ($content -match '(?m)^DATABASE_SSL=') {
    $content = [regex]::Replace($content, '(?m)^DATABASE_SSL=.*$', 'DATABASE_SSL=disable')
} else {
    $content = $content.TrimEnd() + "`nDATABASE_SSL=disable`n"
}
Set-Content -Path $envPath -Value $content -NoNewline -Encoding UTF8

# --- 4. ensure DB exists, then migrate (local) ---
Write-Host "`n==> [4/5] Ensure database '$DbName' exists, then migrate" -ForegroundColor Cyan
npm run db:ensure
if ($LASTEXITCODE -ne 0) { throw "could not ensure database '$DbName' - is a local Postgres running on localhost:$DbPort?" }
npm run migrate
if ($LASTEXITCODE -ne 0) { throw "migrate failed" }

# --- 5. personalize from template ---
Write-Host "`n==> [5/5] init-from-template" -ForegroundColor Cyan
$projectName = ((Split-Path $root -Leaf).ToLower() -replace '[^a-z0-9-]', '-').Trim('-')
$initArgs = @{ ProjectName = $projectName }
# Only fill in the GitHub repo while railway.ts still has the placeholder, so a
# re-run never overwrites a repo you've set by hand.
if ((Get-Content (Join-Path $root ".railway/railway.ts") -Raw) -match 'const GITHUB_REPO = "OWNER/') {
    $owner = $null
    try { $owner = (gh api user --jq .login 2>$null) } catch {}
    if ([string]::IsNullOrWhiteSpace($owner)) {
        Write-Host "    gh not logged in; leaving GITHUB_REPO as OWNER/$projectName (edit .railway/railway.ts later)." -ForegroundColor Yellow
    } else {
        $initArgs.GitHubRepo = "$owner/$projectName"
    }
}
& (Join-Path $scriptsDir "init-from-template.ps1") @initArgs

Write-Host "`nDone. Local dev: 'npm run dev' (http://localhost:3000).  Deploy: 'npm run railway:setup'." -ForegroundColor Green
