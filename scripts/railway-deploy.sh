#!/usr/bin/env bash
# Deploy the current folder to Railway right now, without waiting for a push
# (Bash).
#   ./scripts/railway-deploy.sh
#
# Uploads this directory (respecting .gitignore), builds the Dockerfile on
# Railway, runs the pre-deploy migrations, and swaps traffic over once
# /api/health passes. Uncommitted changes ARE included, so this is handy for a
# quick check; the next push to main replaces it with what's in git.

set -euo pipefail
[ $# -eq 0 ] || { echo "Unknown arg: $1" >&2; exit 1; }

. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
cd "$ROOT"
TOTAL=3

step 1 $TOTAL "Checking Railway CLI + linked project"
assert_railway_cli
assert_railway_login
assert_railway_linked

step 2 $TOTAL "railway up (build + deploy '$WEB_SERVICE')"
railway up --service "$WEB_SERVICE" --ci \
  || die "railway up failed. Build logs: 'railway logs --service $WEB_SERVICE --build'."

step 3 $TOTAL "Live"
DOMAIN="$(get_railway_domain)"
CUSTOM_DOMAIN="$(get_railway_const CUSTOM_DOMAIN)"
[ -z "$DOMAIN" ] || echo "Deployed:  https://$DOMAIN"
[ -z "$CUSTOM_DOMAIN" ] || echo "Custom domain:  https://$CUSTOM_DOMAIN"
if [ -z "$DOMAIN" ] && [ -z "$CUSTOM_DOMAIN" ]; then
  echo "Deployed, but the service has no public domain yet. Run 'npm run railway:domain'."
fi
echo "Logs: 'railway logs --service $WEB_SERVICE'."
