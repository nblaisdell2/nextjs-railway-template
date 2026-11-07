#!/usr/bin/env bash
# First-time Railway deploy, end to end (Bash). Safe to re-run.
#   ./scripts/setup-railway.sh [--yes]
#
# 1) check prerequisites (Railway CLI + login, gh login, git remote, railway.ts filled in)
# 2) link this folder to the Railway project named in .railway/railway.ts
#    (creates it only after you confirm, or with --yes)
# 3) railway config plan (shown), then railway config apply
#    -> Postgres, the web service (GitHub source, Dockerfile, health check,
#       pre-deploy migrations, DATABASE_URL reference), custom domain
# 4) wait for the first deploy (stops with the push command if main isn't pushed yet)
# 5) generate the *.up.railway.app domain if no custom domain is declared
# 6) print the live HTTPS URL (+ DNS records still needed for a custom domain)
#
#   --yes   don't prompt: create the project if missing and pass --yes to
#           `railway config apply`. Destructive changes are never auto-confirmed.

set -euo pipefail

ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
cd "$ROOT"
TOTAL=6

# --- 1. prerequisites ---
step 1 $TOTAL "Checking prerequisites"
assert_railway_cli
if ! railway whoami >/dev/null 2>&1; then
  is_interactive || die "Not logged in to Railway. Run 'railway login' first."
  echo "Not logged in to Railway - opening 'railway login'..."
  railway login || die "railway login failed"
fi
railway whoami
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) not found. Install it from https://cli.github.com/."
gh auth status >/dev/null 2>&1 || die "GitHub CLI isn't logged in. Run 'gh auth login' first."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "This folder isn't a git repository. Create the repo from the template (see README Quick start)."
git remote get-url origin >/dev/null 2>&1 \
  || die "No 'origin' git remote. Railway deploys from GitHub, so push this repo there first."

PROJECT_NAME="$(get_railway_const PROJECT_NAME)"
GITHUB_REPO="$(get_railway_const GITHUB_REPO)"
CUSTOM_DOMAIN="$(get_railway_const CUSTOM_DOMAIN)"
case "$GITHUB_REPO" in
  OWNER/*) die "GITHUB_REPO in .railway/railway.ts is still a placeholder. Run './scripts/init-from-template.sh --name <name> --repo <owner>/<repo>'." ;;
esac
echo "Project: $PROJECT_NAME   Repo: $GITHUB_REPO   Custom domain: ${CUSTOM_DOMAIN:-(none)}"
if [ ! -d "$ROOT/node_modules/railway" ]; then
  echo "Installing npm dependencies (railway.ts needs the 'railway' package)..."
  npm install
fi

# --- 2. link (or create) the Railway project ---
step 2 $TOTAL "Linking Railway project '$PROJECT_NAME'"
if is_railway_linked; then
  echo "Already linked:"
  railway status
elif railway link --project "$PROJECT_NAME" --environment production >/dev/null 2>&1; then
  echo "Linked existing project '$PROJECT_NAME'."
else
  if [ "$ASSUME_YES" != true ]; then
    is_interactive \
      || die "No Railway project '$PROJECT_NAME' is linked. Re-run interactively, pass --yes to create it, or run 'railway link'."
    read -r -p "No Railway project named '$PROJECT_NAME' found. Create it now? [y/N] " answer
    case "$answer" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
  fi
  railway init --name "$PROJECT_NAME" || die "railway init failed"
fi

# --- 3. plan + apply the infrastructure ---
step 3 $TOTAL "railway config plan / apply (.railway/railway.ts)"
railway config plan || die "railway config plan failed"
APPLY_ARGS=()
[ "$ASSUME_YES" = true ] && APPLY_ARGS+=(--yes)
railway config apply ${APPLY_ARGS[@]+"${APPLY_ARGS[@]}"} || die "railway config apply failed (or was declined)"

# --- 4. first deploy ---
step 4 $TOTAL "Waiting for the deploy"
REMOTE_MAIN="$(git ls-remote --heads origin main 2>/dev/null || true)"
if [ -z "$REMOTE_MAIN" ]; then
  echo "Nothing has been pushed to 'main' on GitHub yet, so Railway has nothing to build."
  echo "Push it, then re-run this script:"
  echo ""
  echo "  git add -A"
  echo "  git commit -m \"Initial commit\""
  echo "  git push -u origin main"
  echo "  npm run railway:setup"
  exit 0
fi
LOCAL_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
if [ -n "$LOCAL_HEAD" ] && ! printf '%s' "$REMOTE_MAIN" | grep -q "$LOCAL_HEAD"; then
  echo "Note: your local HEAD isn't what's on origin/main. Railway deploys origin/main; push to ship local commits."
fi

latest_status() {
  railway deployment list --service "$WEB_SERVICE" --limit 1 --json 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      try {
        let j = JSON.parse(s);
        if (Array.isArray(j)) j = j[0]; else if (j && j.deployments) j = j.deployments[0];
        process.stdout.write(j && j.status ? String(j.status) : "");
      } catch { process.stdout.write(""); }
    });' || true
}

START=$(date +%s)
LAST=""
while true; do
  STATUS="$(latest_status)"
  if [ "$STATUS" != "$LAST" ]; then
    echo "  $(date +%H:%M:%S)  ${STATUS:-waiting for Railway to start a deploy...}"
    LAST="$STATUS"
  fi
  case "$STATUS" in
    SUCCESS) break ;;
    FAILED|CRASHED)
      die "The deploy $STATUS. See the logs: 'railway logs --service $WEB_SERVICE --build' (build) or 'railway logs --service $WEB_SERVICE' (runtime / pre-deploy migrations)." ;;
  esac
  ELAPSED=$(( $(date +%s) - START ))
  if [ -z "$STATUS" ] && [ "$ELAPSED" -gt 180 ]; then
    die "No deploy started. Make sure Railway's GitHub app can see '$GITHUB_REPO' (https://github.com/apps/railway-app/installations/new), then re-run this script. To deploy without GitHub right now: 'npm run railway:deploy'."
  fi
  [ "$ELAPSED" -le 1200 ] || die "Timed out waiting for the deploy. Check 'railway logs --service $WEB_SERVICE' or the dashboard ('railway open')."
  sleep 10
done

# --- 5. Railway-provided domain ---
step 5 $TOTAL "Railway domain"
DOMAIN="$(get_railway_domain)"
if [ -n "$DOMAIN" ]; then
  echo "Already has a Railway domain: $DOMAIN"
elif [ -n "$CUSTOM_DOMAIN" ]; then
  echo "Custom domain declared ($CUSTOM_DOMAIN); not generating a *.up.railway.app domain. Run 'npm run railway:domain' if you want one too."
else
  railway domain --service "$WEB_SERVICE" || die "railway domain failed"
  DOMAIN="$(get_railway_domain)"
fi

# --- 6. done ---
step 6 $TOTAL "Live"
if [ -n "$DOMAIN" ]; then
  echo ""
  echo "Your site is live at:  https://$DOMAIN"
fi
if [ -n "$CUSTOM_DOMAIN" ]; then
  echo ""
  echo "Custom domain https://$CUSTOM_DOMAIN needs these DNS records at your DNS provider"
  echo "(BOTH the CNAME and the TXT; without the TXT Railway answers 404). Railway issues the"
  echo "HTTPS certificate automatically once DNS has propagated:"
  railway domain status "$CUSTOM_DOMAIN" --service "$WEB_SERVICE" || true
fi
echo ""
echo "From now on: push to 'main' to deploy. Logs: 'railway logs --service $WEB_SERVICE'."
