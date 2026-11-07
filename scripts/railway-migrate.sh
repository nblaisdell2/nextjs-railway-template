#!/usr/bin/env bash
# Apply migrations to the LIVE Railway database by hand (Bash).
#   ./scripts/railway-migrate.sh [--ssh]
#
# You rarely need this: every deploy already runs `npm run migrate` as its
# pre-deploy command. It's the escape hatch for re-running migrations without
# pushing new code. It always uses the DATABASE_URL Railway injects into the
# web service, never your local .env.
#
# Default: redeploys the current version of `web` (`railway redeploy`), which
# re-runs the pre-deploy `npm run migrate` and swaps traffic once /api/health
# passes. No SSH keys needed, and the database stays private.
#
# --ssh: runs `npm run migrate` inside the running container over `railway ssh`
# instead (no restart, output right here). Needs an SSH key on this machine
# (`ssh-keygen -t ed25519`).
#
# Either way the migrations are the ones in the DEPLOYED image, so push new
# migration files first. (`railway run npm run migrate` won't work: it runs on
# your laptop, where postgres.railway.internal doesn't resolve.)

set -euo pipefail

USE_SSH=false
for arg in "$@"; do
  case "$arg" in
    --ssh) USE_SSH=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
cd "$ROOT"
TOTAL=2

step 1 $TOTAL "Checking Railway CLI + linked project"
assert_railway_cli
assert_railway_login
assert_railway_linked

if [ "$USE_SSH" = true ]; then
  step 2 $TOTAL "npm run migrate inside the '$WEB_SERVICE' container (railway ssh)"
  railway ssh --service "$WEB_SERVICE" -- sh -c "cd /app && npm run migrate" \
    || die "Migration over SSH failed (see output above). Without an SSH key, run this without --ssh."
else
  step 2 $TOTAL "Redeploying '$WEB_SERVICE' (re-runs the pre-deploy migrations)"
  BEFORE="$(latest_deployment)"
  [ -n "$BEFORE" ] || die "'$WEB_SERVICE' has no deployment yet. Run 'npm run railway:setup' first."
  railway redeploy --service "$WEB_SERVICE" --yes || die "railway redeploy failed"
  wait_for_deploy "${BEFORE%% *}" "Check the dashboard ('railway open')."
  echo ""
  echo "Migration output (from the pre-deploy step):"
  railway logs --service "$WEB_SERVICE" --lines 200 2>/dev/null \
    | grep -E '^(\+ apply|= skip|Done\.|Failed on)' | sed 's/^/  /' || true
fi

echo ""
echo "Migrations applied to the Railway database."
