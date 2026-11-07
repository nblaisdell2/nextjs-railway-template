#!/usr/bin/env bash
# First-time Railway deploy, end to end (Bash). Safe to re-run.
#   ./scripts/setup-railway.sh [--yes]
#
# 1) check prerequisites (Railway CLI + login, gh login, git remote, railway.ts filled in)
# 2) link this folder to the Railway project named in .railway/railway.ts
#    (creates it only after you confirm, or with --yes)
# 3) railway config plan (shown), then railway config apply
#    -> Postgres, the web service (GitHub source, Dockerfile, health check,
#       pre-deploy migrations, DATABASE_URL reference)
# 4) wait for the first deploy (stops with the push command if main isn't pushed yet)
# 5) generate the *.up.railway.app domain; attach CUSTOM_DOMAIN if one is set
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
railway_config plan || die "railway config plan failed"
APPLY_ARGS=()
[ "$ASSUME_YES" = true ] && APPLY_ARGS+=(--yes)
railway_config apply ${APPLY_ARGS[@]+"${APPLY_ARGS[@]}"} || die "railway config apply failed (or was declined)"

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

wait_for_deploy "" "Railway's GitHub app may not have access to '$GITHUB_REPO': open the project ('railway open') -> web -> Settings -> Source and connect the repo, then re-run this script. To deploy without GitHub right now: 'npm run railway:deploy'."

# --- 5. domains ---
# The generated domain is always created: with a custom domain it's how you
# reach the site while DNS propagates.
step 5 $TOTAL "Domains"
DOMAIN="$(get_railway_domain)"
if [ -n "$DOMAIN" ]; then
  echo "Railway domain: $DOMAIN"
else
  railway domain --service "$WEB_SERVICE" >/dev/null || die "railway domain failed"
  DOMAIN="$(get_railway_domain)"
  echo "Generated Railway domain: $DOMAIN"
fi
if [ -n "$CUSTOM_DOMAIN" ]; then
  echo ""
  add_custom_domain "$CUSTOM_DOMAIN"
fi

# --- 6. done ---
step 6 $TOTAL "Live"
[ -z "$DOMAIN" ] || echo "Your site is live at:  https://$DOMAIN"
[ -z "$CUSTOM_DOMAIN" ] || echo "Custom domain:         https://$CUSTOM_DOMAIN  (after the DNS records above are added and verified)"
echo ""
echo "From now on: push to 'main' to deploy. Logs: 'railway logs --service $WEB_SERVICE'."
