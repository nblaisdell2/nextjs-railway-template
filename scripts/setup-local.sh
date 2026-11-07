#!/usr/bin/env bash
# One-shot local onboarding for a freshly cloned project (Bash).
#   ./scripts/setup-local.sh [--password=...] [--db-name=test] [--db-port=5432]
#
# 1) prompt for the local Postgres password (hidden input)
# 2) npm install
# 3) write .env (DATABASE_URL -> local database, default name "test"; DATABASE_SSL=disable)
# 4) create that database if missing, then apply migrations
# 5) personalize from the template (project name = folder, repo = <gh-user>/<folder>)
#
# Prereq for step 4: a local Postgres is running, e.g.
#   docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

set -euo pipefail

DB_NAME="test"
DB_PORT="5432"
DB_PASSWORD=""
for arg in "$@"; do
  case "$arg" in
    --password=*) DB_PASSWORD="${arg#*=}" ;;
    --db-name=*)  DB_NAME="${arg#*=}" ;;
    --db-port=*)  DB_PORT="${arg#*=}" ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
cd "$ROOT"

urlencode() { # URL-safe encode of $1
  local s="$1" out="" i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in [a-zA-Z0-9.~_-]) out+="$c" ;; *) out+=$(printf '%%%02X' "'$c") ;; esac
  done
  printf '%s' "$out"
}

echo "==> [1/5] Local Postgres password"
if [ -z "$DB_PASSWORD" ]; then
  read -r -s -p "Local Postgres password: " DB_PASSWORD; echo
fi
[ -n "$DB_PASSWORD" ] || { echo "Database password is required." >&2; exit 1; }

echo ""
echo "==> [2/5] npm install"
npm install

echo ""
echo "==> [3/5] Writing .env (database '$DB_NAME')"
ENC="$(urlencode "$DB_PASSWORD")"
DBURL="postgres://postgres:$ENC@localhost:$DB_PORT/$DB_NAME"
if [ -f .env.example ]; then cp .env.example .env; else printf 'DATABASE_URL=\nDATABASE_SSL=disable\n' > .env; fi
# The encoded password only contains [A-Za-z0-9.~_-%], so it is safe in sed.
if grep -q '^DATABASE_URL=' .env; then
  sed -i.bak -E "s|^DATABASE_URL=.*|DATABASE_URL=$DBURL|" .env && rm -f .env.bak
else
  printf 'DATABASE_URL=%s\n%s' "$DBURL" "$(cat .env)" > .env
fi
if grep -q '^DATABASE_SSL=' .env; then
  sed -i.bak -E "s|^DATABASE_SSL=.*|DATABASE_SSL=disable|" .env && rm -f .env.bak
else
  printf '\nDATABASE_SSL=disable\n' >> .env
fi

echo ""
echo "==> [4/5] Ensure database '$DB_NAME' exists, then migrate"
npm run db:ensure || { echo "could not ensure database '$DB_NAME' - is a local Postgres running on localhost:$DB_PORT?" >&2; exit 1; }
npm run migrate || { echo "migrate failed" >&2; exit 1; }

echo ""
echo "==> [5/5] init-from-template"
PROJECT_NAME="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]/-/g; s/^-+//; s/-+$//')"
INIT_ARGS=(--name "$PROJECT_NAME")
# Only fill in the GitHub repo while railway.ts still has the placeholder, so a
# re-run never overwrites a repo you've set by hand.
if grep -q 'const GITHUB_REPO = "OWNER/' .railway/railway.ts; then
  OWNER="$(gh api user --jq .login 2>/dev/null || true)"
  if [ -z "$OWNER" ]; then
    echo "    gh not logged in; leaving GITHUB_REPO as OWNER/$PROJECT_NAME (edit .railway/railway.ts later)."
  else
    INIT_ARGS+=(--repo "$OWNER/$PROJECT_NAME")
  fi
fi
bash "$SCRIPTS_DIR/init-from-template.sh" "${INIT_ARGS[@]}"

echo ""
echo "Done. Local dev: 'npm run dev' (http://localhost:3000).  Deploy: 'npm run railway:setup'."
