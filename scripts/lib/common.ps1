# Shared helpers, dot-sourced by the railway-* PowerShell scripts:
#   . (Join-Path $PSScriptRoot "lib/common.ps1")
# Keep in sync with scripts/lib/common.sh.

$Root       = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$RailwayTs  = Join-Path $Root ".railway/railway.ts"
$WebService = "web"        # service names declared in .railway/railway.ts
$DbService  = "postgres"

function Write-Step([int]$n, [int]$total, [string]$label) {
    Write-Host ""
    Write-Host "==> [$n/$total] $label" -ForegroundColor Cyan
}

function Test-Interactive {
    return (-not [Console]::IsInputRedirected) -and [Environment]::UserInteractive
}

# Read a `const NAME = "value";` line from .railway/railway.ts.
function Get-RailwayConst([string]$name) {
    if (-not (Test-Path $RailwayTs)) { throw ".railway/railway.ts not found." }
    $m = Select-String -Path $RailwayTs -Pattern "^\s*const\s+$name\s*=\s*`"([^`"]*)`"\s*;"
    if (-not $m) { throw "Could not find 'const $name = `"...`";' in .railway/railway.ts." }
    return $m.Matches[0].Groups[1].Value
}

# Rewrite a `const NAME = "value";` line in .railway/railway.ts.
function Set-RailwayConst([string]$name, [string]$value) {
    $content = Get-Content $RailwayTs -Raw
    $pattern = "(?m)^(\s*const\s+$name\s*=\s*)`"[^`"]*`"(\s*;)"
    if ($content -notmatch $pattern) { throw "Could not find 'const $name = `"...`";' in .railway/railway.ts." }
    $content = [regex]::Replace($content, $pattern, { param($m) $m.Groups[1].Value + '"' + $value + '"' + $m.Groups[2].Value })
    Set-Content -Path $RailwayTs -Value $content -NoNewline -Encoding UTF8
}

function Assert-RailwayCli {
    if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
        throw "Railway CLI not found. Install it with 'npm install -g @railway/cli' (see https://docs.railway.com/cli)."
    }
}

function Assert-RailwayLogin {
    railway whoami *> $null
    if ($LASTEXITCODE -ne 0) { throw "Not logged in to Railway. Run 'railway login' first." }
}

function Test-RailwayLinked {
    railway status --json *> $null
    return ($LASTEXITCODE -eq 0)
}

function Assert-RailwayLinked {
    if (-not (Test-RailwayLinked)) {
        throw "This folder isn't linked to a Railway project. Run 'npm run railway:setup' first (or 'railway link')."
    }
}

# The web service's Railway-provided domain (e.g. my-app.up.railway.app), or "".
function Get-RailwayDomain {
    $json = railway variables --service $WebService --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return "" }
    $vars = ($json | Out-String) | ConvertFrom-Json
    $d = $vars.RAILWAY_PUBLIC_DOMAIN
    if ($d) { return [string]$d } else { return "" }
}
