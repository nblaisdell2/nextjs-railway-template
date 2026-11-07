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

# `railway config <plan|apply> ...`, with a Windows workaround: the `railway/iac`
# package checks the CLI version by spawning `$env:_` (or "railway") without a
# shell, which can't run npm's railway.cmd shim. Point it at the real
# railway.exe that the npm package ships.
function Invoke-RailwayConfig {
    if ($IsWindows -and -not (Get-Command railway.exe -ErrorAction SilentlyContinue)) {
        $npmRoot = (npm root -g 2>$null)
        $exe = if ($npmRoot) { Join-Path $npmRoot "@railway/cli/bin/railway.exe" }
        if ($exe -and (Test-Path $exe)) { $env:_ = $exe }
    }
    railway config @args
}

# Latest deployment of the web service ({ id, status, ... }) or $null.
function Get-LatestDeployment {
    $json = railway deployment list --service $WebService --limit 1 --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    $parsed = ($json | Out-String) | ConvertFrom-Json
    if ($parsed -is [array]) { return $parsed | Select-Object -First 1 }
    return $parsed
}

# Wait until the web service's latest deployment (newer than -AfterId, if
# given) is SUCCESS. Throws on FAILED/CRASHED, if none starts within
# -StartMinutes, or after -TimeoutMinutes.
function Wait-RailwayDeploy([string]$AfterId = "", [int]$StartMinutes = 3, [int]$TimeoutMinutes = 20, [string]$NoStartHint = "") {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $startDeadline = (Get-Date).AddMinutes($StartMinutes)
    $last = ""
    while ($true) {
        $dep = Get-LatestDeployment
        if ($dep -and $AfterId -and [string]$dep.id -eq $AfterId) { $dep = $null }
        $status = if ($dep) { [string]$dep.status } else { "" }
        if ($status -ne $last) {
            Write-Host ("  {0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $(if ($status) { $status } else { "waiting for Railway to start a deploy..." }))
            $last = $status
        }
        if ($status -eq "SUCCESS") { return }
        if ($status -in @("FAILED", "CRASHED")) {
            throw "The deploy $status. See the logs: 'railway logs --service $WebService --build' (build) or 'railway logs --service $WebService' (runtime / pre-deploy migrations)."
        }
        if (-not $dep -and (Get-Date) -gt $startDeadline) { throw "No deploy started. $NoStartHint" }
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for the deploy. Check 'railway logs --service $WebService' or the dashboard ('railway open')." }
        Start-Sleep -Seconds 10
    }
}

# Domain names attached to the web service (generated and custom).
function Get-RailwayDomainNames {
    $json = railway domain list --service $WebService --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
    $parsed = ($json | Out-String) | ConvertFrom-Json
    return @($parsed.domains | ForEach-Object { [string]$_.domain })
}

# Attach a custom domain to the web service if it isn't already, then print
# its status and the DNS records to add (CNAME + TXT).
function Add-RailwayCustomDomain([string]$domain) {
    if ((Get-RailwayDomainNames) -contains $domain) {
        Write-Host "$domain is already attached to '$WebService'."
    } else {
        railway domain $domain --service $WebService | Out-Null
        # The domain list can lag a few seconds behind the create.
        $attached = $false
        foreach ($i in 1..5) {
            if ((Get-RailwayDomainNames) -contains $domain) { $attached = $true; break }
            Start-Sleep -Seconds 3
        }
        if (-not $attached) { throw "Could not attach $domain (is it already used by another Railway service?)." }
        Write-Host "Attached $domain to '$WebService'."
    }
    railway domain status $domain --service $WebService
    Write-Host ""
    Write-Host "Add BOTH DNS records above at your DNS provider:" -ForegroundColor Yellow
    Write-Host "  - the CNAME routes traffic to Railway"
    Write-Host "  - the TXT (_railway-verify...) proves you own the domain; without it Railway answers 404"
    Write-Host "Using Cloudflare? Keep these records DNS-only (grey cloud) at least until the certificate is"
    Write-Host "issued, and nested subdomains (a.b.example.com) need DNS-only unless you have Advanced Certificate Manager."
    Write-Host "Railway issues the HTTPS certificate automatically once DNS propagates. Check with:"
    Write-Host "  railway domain status $domain --service $WebService"
}

# The web service's Railway-provided domain (e.g. my-app.up.railway.app), or "".
# (Not RAILWAY_PUBLIC_DOMAIN: that switches to the custom domain once one exists.)
function Get-RailwayDomain {
    $json = railway domain list --service $WebService --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return "" }
    $parsed = ($json | Out-String) | ConvertFrom-Json
    $d = @($parsed.domains | Where-Object { $_.type -eq "service" }) | Select-Object -First 1
    if ($d) { return [string]$d.domain } else { return "" }
}
