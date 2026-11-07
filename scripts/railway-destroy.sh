#!/usr/bin/env bash
# Tear down EVERYTHING this project created on Railway (Bash).
#   ./scripts/railway-destroy.sh [--yes]
#
# Deletes the whole Railway project: the web service, the Postgres database
# AND ALL ITS DATA, domains and variables. Your code on GitHub and your local
# files are untouched. Take a backup first if you want to keep the data.
#   --yes   skip the "type the project name" confirmation

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
TOTAL=3

step 1 $TOTAL "Finding the linked Railway project"
assert_railway_cli
assert_railway_login
assert_railway_linked
STATUS_JSON="$(railway status --json)"
PROJECT_ID="$(printf '%s' "$STATUS_JSON" | json_field id)"
PROJECT_NAME="$(printf '%s' "$STATUS_JSON" | json_field name)"
[ -n "$PROJECT_ID" ] && [ -n "$PROJECT_NAME" ] \
  || die "Could not read the linked project's id/name from 'railway status --json'."
DECLARED="$(get_railway_const PROJECT_NAME)"
if [ "$DECLARED" != "$PROJECT_NAME" ]; then
  echo "Note: the linked project is '$PROJECT_NAME' but .railway/railway.ts declares '$DECLARED'."
fi

step 2 $TOTAL "Confirm"
echo "This will DELETE the Railway project '$PROJECT_NAME' ($PROJECT_ID):"
echo "  - service '$WEB_SERVICE' and all its deployments and domains"
echo "  - service '$DB_SERVICE' (PostgreSQL) and ALL ITS DATA"
echo "  - every variable in the project"
echo "GitHub and your local files are not touched."
echo ""
echo "Want the data? Backups live inside the project and are deleted with it, so take a"
echo "pg_dump first (README -> 'Cost and teardown' -> 'Reaching the database from your laptop')."
if [ "$ASSUME_YES" != true ]; then
  is_interactive || die "Refusing to delete without confirmation. Re-run interactively or pass --yes."
  read -r -p "Type the project name ('$PROJECT_NAME') to confirm: " answer
  [ "$answer" = "$PROJECT_NAME" ] || { echo "Aborted."; exit 1; }
fi

step 3 $TOTAL "railway delete"
railway delete --project "$PROJECT_ID" --yes \
  || die "railway delete failed (accounts with 2FA may need --2fa-code; or delete it in the dashboard)"
railway unlink >/dev/null 2>&1 || true
echo ""
echo "Deleted: the site goes offline now; Railway purges the project after a grace period (about 48h). This folder is now unlinked."
echo "To deploy again later: npm run railway:setup"
