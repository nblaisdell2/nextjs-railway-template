# One-time personalization after "Use this template" (PowerShell).
#
#   .\scripts\init-from-template.ps1 -ProjectName my-app `
#       [-GitHubRepo owner/my-app] [-CustomDomain app.example.com]
#
# OFFLINE: it only rewrites files in this repo (no Railway, no network), so you
# can review everything with `git diff` before anything exists in Railway.
#   - replaces the template's placeholder project name in .railway/railway.ts,
#     package.json, package-lock.json, README.md and CLAUDE.md
#   - writes the GitHub repo Railway deploys from into .railway/railway.ts
#   - optionally writes a custom domain into .railway/railway.ts
# Safe to re-run: the -GitHubRepo / -CustomDomain values are (re)written each time.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
    [string]$GitHubRepo,
    [string]$CustomDomain
)

$ErrorActionPreference = "Stop"

if ($ProjectName -cnotmatch '^[a-z][a-z0-9-]{1,28}[a-z0-9]$') {
    throw "ProjectName must be lowercase letters/digits/hyphens, 3-30 chars, starting with a letter (e.g. 'my-app'). The Railway project is named after it."
}
if ($GitHubRepo -and $GitHubRepo -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$') {
    throw "GitHubRepo must look like 'owner/repo'."
}
if ($CustomDomain) {
    $CustomDomain = $CustomDomain.Trim().ToLower() -replace '^https?://', '' -replace '/.*$', ''
    if ($CustomDomain -notmatch '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$') {
        throw "CustomDomain must be a hostname like 'app.example.com' (no scheme or path)."
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OLD  = "nextjs-test"

function Replace-In([string]$rel, [string]$from, [string]$to) {
    $p = Join-Path $root $rel
    if (Test-Path $p) {
        (Get-Content $p -Raw) -replace [regex]::Escape($from), $to |
            Set-Content $p -NoNewline -Encoding UTF8
    }
}

function Set-Const([string]$name, [string]$value) {
    $p = Join-Path $root ".railway/railway.ts"
    $content = Get-Content $p -Raw
    $pattern = "(?m)^(\s*const\s+$name\s*=\s*)`"[^`"]*`"(\s*;)"
    if ($content -notmatch $pattern) { throw "Could not find 'const $name = `"...`";' in .railway/railway.ts." }
    $content = [regex]::Replace($content, $pattern, { param($m) $m.Groups[1].Value + '"' + $value + '"' + $m.Groups[2].Value })
    Set-Content -Path $p -Value $content -NoNewline -Encoding UTF8
}

# 1. Replace the project identity token.
$projectFiles = @(".railway/railway.ts", "package.json", "package-lock.json", "README.md", "CLAUDE.md")
foreach ($f in $projectFiles) { Replace-In $f $OLD $ProjectName }

# 2. GitHub repo Railway deploys from (deploy-on-push source).
if ($GitHubRepo) { Set-Const "GITHUB_REPO" $GitHubRepo }

# 3. Optional custom domain.
if ($CustomDomain) { Set-Const "CUSTOM_DOMAIN" $CustomDomain }

$ts = Get-Content (Join-Path $root ".railway/railway.ts") -Raw
$repoNow   = [regex]::Match($ts, 'const GITHUB_REPO = "([^"]*)"').Groups[1].Value
$domainNow = [regex]::Match($ts, 'const CUSTOM_DOMAIN = "([^"]*)"').Groups[1].Value

Write-Host ""
Write-Host "Personalized to '$ProjectName'."
Write-Host "  GitHub repo:   $repoNow"
Write-Host "  Custom domain: $(if ($domainNow) { $domainNow } else { '(none - the generated *.up.railway.app domain will be used)' })"
if ($repoNow -like "OWNER/*") {
    Write-Host "  WARNING: GITHUB_REPO is still a placeholder. Re-run with -GitHubRepo <owner>/<repo>." -ForegroundColor Yellow
}
Write-Host "Next:"
Write-Host "  1. Review changes:  git diff"
Write-Host "  2. Commit and push to main"
Write-Host "  3. npm run railway:setup"
