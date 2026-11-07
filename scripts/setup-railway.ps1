# First-time Railway deploy, end to end (PowerShell). Safe to re-run.
#   npm run railway:setup     (or: .\scripts\setup-railway.ps1 [-Yes])
#
# 1) check prerequisites (Railway CLI + login, gh login, git remote, railway.ts filled in)
# 2) link this folder to the Railway project named in .railway/railway.ts
#    (creates it only after you confirm, or with -Yes)
# 3) railway config plan (shown), then railway config apply
#    -> Postgres, the web service (GitHub source, Dockerfile, health check,
#       pre-deploy migrations, DATABASE_URL reference), custom domain
# 4) wait for the first deploy (stops with the push command if main isn't pushed yet)
# 5) generate the *.up.railway.app domain if no custom domain is declared
# 6) print the live HTTPS URL (+ DNS records still needed for a custom domain)
#
#   -Yes   don't prompt: create the project if missing and pass --yes to
#          `railway config apply`. Destructive changes are never auto-confirmed.

[CmdletBinding()]
param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/common.ps1")
Set-Location $Root
$total = 6

# --- 1. prerequisites ---
Write-Step 1 $total "Checking prerequisites"
Assert-RailwayCli
railway whoami *> $null
if ($LASTEXITCODE -ne 0) {
    if (-not (Test-Interactive)) { throw "Not logged in to Railway. Run 'railway login' first." }
    Write-Host "Not logged in to Railway - opening 'railway login'..."
    railway login
    if ($LASTEXITCODE -ne 0) { throw "railway login failed" }
}
railway whoami
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI (gh) not found. Install it from https://cli.github.com/." }
gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI isn't logged in. Run 'gh auth login' first." }
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { throw "This folder isn't a git repository. Create the repo from the template (see README Quick start)." }
git remote get-url origin *> $null
if ($LASTEXITCODE -ne 0) { throw "No 'origin' git remote. Railway deploys from GitHub, so push this repo there first." }

$projectName  = Get-RailwayConst "PROJECT_NAME"
$githubRepo   = Get-RailwayConst "GITHUB_REPO"
$customDomain = Get-RailwayConst "CUSTOM_DOMAIN"
if ($githubRepo -like "OWNER/*") {
    throw "GITHUB_REPO in .railway/railway.ts is still a placeholder. Run 'npm run template:init -- -ProjectName <name> -GitHubRepo <owner>/<repo>'."
}
Write-Host "Project: $projectName   Repo: $githubRepo   Custom domain: $(if ($customDomain) { $customDomain } else { '(none)' })"
if (-not (Test-Path (Join-Path $Root "node_modules/railway"))) {
    Write-Host "Installing npm dependencies (railway.ts needs the 'railway' package)..."
    npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
}

# --- 2. link (or create) the Railway project ---
Write-Step 2 $total "Linking Railway project '$projectName'"
if (Test-RailwayLinked) {
    Write-Host "Already linked:"
    railway status
} else {
    railway link --project $projectName --environment production *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Linked existing project '$projectName'."
    } else {
        if (-not $Yes) {
            if (-not (Test-Interactive)) {
                throw "No Railway project '$projectName' is linked. Re-run interactively, pass -Yes to create it, or run 'railway link'."
            }
            $answer = Read-Host "No Railway project named '$projectName' found. Create it now? [y/N]"
            if ($answer -notmatch '^(y|yes)$') { Write-Host "Aborted."; exit 1 }
        }
        railway init --name $projectName
        if ($LASTEXITCODE -ne 0) { throw "railway init failed" }
    }
}

# --- 3. plan + apply the infrastructure ---
Write-Step 3 $total "railway config plan / apply (.railway/railway.ts)"
railway config plan
if ($LASTEXITCODE -ne 0) { throw "railway config plan failed" }
$applyArgs = @()
if ($Yes) { $applyArgs += "--yes" }
railway config apply @applyArgs
if ($LASTEXITCODE -ne 0) { throw "railway config apply failed (or was declined)" }

# --- 4. first deploy ---
Write-Step 4 $total "Waiting for the deploy"
$remoteMain = git ls-remote --heads origin main 2>$null
if (-not $remoteMain) {
    Write-Host "Nothing has been pushed to 'main' on GitHub yet, so Railway has nothing to build." -ForegroundColor Yellow
    Write-Host "Push it, then re-run this script:"
    Write-Host ""
    Write-Host "  git add -A"
    Write-Host "  git commit -m `"Initial commit`""
    Write-Host "  git push -u origin main"
    Write-Host "  npm run railway:setup"
    exit 0
}
$localHead = git rev-parse HEAD 2>$null
if ($localHead -and ($remoteMain -notmatch [regex]::Escape($localHead))) {
    Write-Host "Note: your local HEAD isn't what's on origin/main. Railway deploys origin/main; push to ship local commits." -ForegroundColor Yellow
}

function Get-LatestDeployment {
    $json = railway deployment list --service $WebService --limit 1 --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    $parsed = ($json | Out-String) | ConvertFrom-Json
    if ($parsed -is [array]) { return $parsed | Select-Object -First 1 }
    if ($parsed.deployments) { return $parsed.deployments | Select-Object -First 1 }
    return $parsed
}

$deadline = (Get-Date).AddMinutes(20)
$noDeployDeadline = (Get-Date).AddMinutes(3)
$lastStatus = ""
while ($true) {
    $dep = Get-LatestDeployment
    $status = if ($dep) { [string]$dep.status } else { "" }
    if ($status -ne $lastStatus) {
        Write-Host ("  {0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $(if ($status) { $status } else { "waiting for Railway to start a deploy..." }))
        $lastStatus = $status
    }
    if ($status -eq "SUCCESS") { break }
    if ($status -in @("FAILED", "CRASHED")) {
        throw "The deploy $status. See the logs: 'railway logs --service $WebService --build' (build) or 'railway logs --service $WebService' (runtime / pre-deploy migrations)."
    }
    if (-not $dep -and (Get-Date) -gt $noDeployDeadline) {
        throw ("No deploy started. Make sure Railway's GitHub app can see '$githubRepo' " +
               "(https://github.com/apps/railway-app/installations/new), then re-run this script. " +
               "To deploy without GitHub right now: 'npm run railway:deploy'.")
    }
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for the deploy. Check 'railway logs --service $WebService' or the dashboard ('railway open')." }
    Start-Sleep -Seconds 10
}

# --- 5. Railway-provided domain ---
Write-Step 5 $total "Railway domain"
$domain = Get-RailwayDomain
if ($domain) {
    Write-Host "Already has a Railway domain: $domain"
} elseif ($customDomain) {
    Write-Host "Custom domain declared ($customDomain); not generating a *.up.railway.app domain. Run 'npm run railway:domain' if you want one too."
} else {
    railway domain --service $WebService
    if ($LASTEXITCODE -ne 0) { throw "railway domain failed" }
    $domain = Get-RailwayDomain
}

# --- 6. done ---
Write-Step 6 $total "Live"
if ($domain) {
    Write-Host ""
    Write-Host "Your site is live at:  https://$domain" -ForegroundColor Green
}
if ($customDomain) {
    Write-Host ""
    Write-Host "Custom domain https://$customDomain needs these DNS records at your DNS provider" -ForegroundColor Yellow
    Write-Host "(BOTH the CNAME and the TXT; without the TXT Railway answers 404). Railway issues the"
    Write-Host "HTTPS certificate automatically once DNS has propagated:"
    railway domain status $customDomain --service $WebService
}
Write-Host ""
Write-Host "From now on: push to 'main' to deploy. Logs: 'railway logs --service $WebService'."
