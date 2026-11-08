# One-shot local onboarding for a freshly cloned project (PowerShell).
#   npm run setup [-DbName my_db] [-DbPort 5433]     (any order, with or without `--`)
#   .\scripts\setup-local.ps1 [-DbName my_db] [-DbPort 5433]
#
# 1) prompt for the local Postgres password (hidden input)
# 2) npm install
# 3) write .env (DATABASE_URL -> local database; DATABASE_SSL=disable). With no
#    -DbName: reuse the database already in .env, else name it after the project
#    folder, adding a random suffix if that name is taken (db/choose-database-name.mjs)
# 4) create that database if missing, then apply migrations
# 5) personalize from the template (project name = folder, repo = <gh-user>/<folder>)
#
# The password is deliberately not an argument: arguments end up in your
# terminal, your shell history and npm's command echo. For automation, set the
# standard PGPASSWORD environment variable instead.
#
# Without `--`, npm consumes the -DbName / -DbPort flags and passes only their
# values, so bare values are sorted by shape: all digits is the port, anything
# else is the database name (a valid name can't start with a digit).
#
# Prereq for step 4: a local Postgres is running, e.g.
#   docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$DbName,
    [string]$DbPort,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"
$scriptsDir = $PSScriptRoot
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

# --- check the arguments before asking for anything ---
foreach ($arg in $Rest) {
    if ($arg -like "-*") {
        # Print only the flag's name: what follows it could be a password.
        $flag = ($arg -split '[:=]', 2)[0]
        throw "Unknown option '$flag'. Options: -DbName <name>, -DbPort <port>. The password is never an argument: setup asks for it (or set PGPASSWORD)."
    }
    if ($arg -match '^\d+$') {
        if ($DbPort) { throw "More than one port was given." }
        $DbPort = $arg
    } else {
        if ($DbName) { throw "More than one database name was given." }
        $DbName = $arg
    }
}
if ($DbName -and $DbName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    # Don't print the value: it could be a password typed in the wrong place.
    throw "That database name isn't valid. Use letters, digits and underscores, starting with a letter or underscore."
}
if (-not $DbPort) { $DbPort = "5432" }
if ($DbPort -notmatch '^\d{1,5}$' -or [int]$DbPort -lt 1 -or [int]$DbPort -gt 65535) {
    throw "That port isn't valid. Use a number from 1 to 65535."
}

# --- 1. password ---
Write-Host "==> [1/5] Local Postgres password" -ForegroundColor Cyan
if ($env:PGPASSWORD) {
    $DbPassword = $env:PGPASSWORD
    Write-Host "Using the password from the PGPASSWORD environment variable."
} else {
    $secure = Read-Host "Local Postgres password" -AsSecureString
    $DbPassword = [System.Net.NetworkCredential]::new("", $secure).Password
}
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw "Database password is required." }

# --- 2. npm install ---
Write-Host "`n==> [2/5] npm install" -ForegroundColor Cyan
npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed" }

# --- 3. .env ---
$enc = [uri]::EscapeDataString($DbPassword)   # URL-safe password
Write-Host ""
if (-not $DbName) {
    $env:SETUP_ADMIN_URL = "postgres://postgres:$enc@localhost:$DbPort/postgres"
    try {
        $DbName = node db/choose-database-name.mjs
        $chooseExit = $LASTEXITCODE
    } finally {
        Remove-Item Env:SETUP_ADMIN_URL -ErrorAction SilentlyContinue
    }
    if ($chooseExit -ne 0 -or -not $DbName) {
        throw "could not choose a database name - is a local Postgres running on localhost:$DbPort, and is the password right?"
    }
}
Write-Host "==> [3/5] Writing .env (database '$DbName')" -ForegroundColor Cyan
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
