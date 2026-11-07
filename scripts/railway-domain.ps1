# Generate the Railway domain, or attach a custom domain (PowerShell).
#   npm run railway:domain                          -> generated *.up.railway.app domain
#   npm run railway:domain -- app.example.com       -> custom domain
#
# Custom domain: the domain is written into CUSTOM_DOMAIN in .railway/railway.ts
# and attached with `railway config apply`, so the file stays the source of
# truth (a domain added only with `railway domain <d>` would be REMOVED by the
# next `railway config apply`). Then it prints the DNS records to add at your
# DNS provider: a CNAME (where traffic goes) AND a TXT (proves you own the
# domain; without it Railway answers 404). Railway issues the Let's Encrypt
# certificate automatically once DNS has propagated.

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Domain,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/common.ps1")
Set-Location $Root

if (-not $Domain) {
    $total = 2
    Write-Step 1 $total "Checking Railway CLI + linked project"
    Assert-RailwayCli; Assert-RailwayLogin; Assert-RailwayLinked

    Write-Step 2 $total "Railway-provided domain for '$WebService'"
    $existing = Get-RailwayDomain
    if ($existing) {
        Write-Host "Already has one: https://$existing" -ForegroundColor Green
        exit 0
    }
    railway domain --service $WebService
    if ($LASTEXITCODE -ne 0) { throw "railway domain failed" }
    $d = Get-RailwayDomain
    if ($d) { Write-Host "`nLive at:  https://$d" -ForegroundColor Green }
    exit 0
}

$Domain = $Domain.Trim().ToLower() -replace '^https?://', '' -replace '/.*$', ''
if ($Domain -notmatch '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$') {
    throw "'$Domain' doesn't look like a hostname (e.g. app.example.com)."
}
$total = 4

Write-Step 1 $total "Checking Railway CLI + linked project"
Assert-RailwayCli; Assert-RailwayLogin; Assert-RailwayLinked

Write-Step 2 $total "Writing CUSTOM_DOMAIN = `"$Domain`" into .railway/railway.ts"
$previous = Get-RailwayConst "CUSTOM_DOMAIN"
if ($previous -and $previous -ne $Domain) {
    Write-Host "Replacing the previous custom domain '$previous' (it will be detached)." -ForegroundColor Yellow
}
Set-RailwayConst "CUSTOM_DOMAIN" $Domain

Write-Step 3 $total "railway config plan / apply"
railway config plan
if ($LASTEXITCODE -ne 0) { throw "railway config plan failed" }
$applyArgs = @()
if ($Yes) { $applyArgs += "--yes" }
railway config apply @applyArgs
if ($LASTEXITCODE -ne 0) { throw "railway config apply failed (or was declined). .railway/railway.ts was already edited; revert with 'git checkout .railway/railway.ts' if needed." }

Write-Step 4 $total "DNS records for $Domain"
railway domain status $Domain --service $WebService
if ($LASTEXITCODE -ne 0) { throw "railway domain status failed" }

Write-Host ""
Write-Host "Add BOTH records above at your DNS provider:" -ForegroundColor Yellow
Write-Host "  - CNAME  $Domain -> the Railway target shown above (routes the traffic)"
Write-Host "  - TXT    the verification record shown above (proves ownership; missing TXT = 404)"
Write-Host "Using Cloudflare? Keep '_acme-challenge' records DNS-only, and nested subdomains"
Write-Host "(a.b.example.com) DNS-only (grey cloud) unless you have Advanced Certificate Manager."
Write-Host "Railway issues the HTTPS certificate once DNS propagates. Check progress with:"
Write-Host "  railway domain status $Domain --service $WebService"
Write-Host "Commit .railway/railway.ts so the domain stays declared."
