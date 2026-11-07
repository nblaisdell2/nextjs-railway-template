#!/usr/bin/env bash
# Apply migrations to the LIVE Railway database by hand (Bash).
#   ./scripts/railway-migrate.sh
#
# You rarely need this: every deploy already runs `npm run migrate` as its
# pre-deploy command. It's the escape hatch for re-running migrations without
# a deploy.
#
# It runs `npm run migrate` INSIDE the running web container over `railway ssh`,
# so it uses the DATABASE_URL Railway injects there (the private-network URL)
# and never your local .env. (`railway run` would run on your laptop, where
# postgres.railway.internal doesn't resolve.) The container holds the migration
# files of the version that's deployed, so push new migrations first.

set -euo pipefail
[ $# -eq 0 ] || { echo "Unknown arg: $1" >&2; exit 1; }

. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
cd "$ROOT"
TOTAL=2

step 1 $TOTAL "Checking Railway CLI + linked project"
assert_railway_cli
assert_railway_login
assert_railway_linked

step 2 $TOTAL "npm run migrate inside the '$WEB_SERVICE' container"
railway ssh --service "$WEB_SERVICE" -- sh -c "cd /app && npm run migrate" \
  || die "Migration failed (see output above). Logs: 'railway logs --service $WEB_SERVICE'."

echo ""
echo "Migrations applied to the Railway database."
