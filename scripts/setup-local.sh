#!/usr/bin/env bash
# One-shot local onboarding for a freshly cloned project (Bash).
#   ./scripts/setup-local.sh [--db-name=my_db] [--db-port=5433]     (any order)
#
# 1) prompt for the local Postgres password (hidden input)
# 2) npm install
# 3) write .env (DATABASE_URL -> local database; DATABASE_SSL=disable). With no
#    --db-name: reuse the database already in .env, else name it after the project
#    folder, adding a random suffix if that name is taken (db/choose-database-name.mjs)
# 4) create that database if missing, then apply migrations
# 5) personalize from the template (project name = folder, repo = <gh-user>/<folder>)
#
# The password is deliberately not an argument: arguments end up in your
# terminal and your shell history. For automation, set the standard PGPASSWORD
# environment variable instead.
#
# Bare values are also accepted and sorted by shape, matching the PowerShell
# version: all digits is the port, anything else is the database name (a valid
# name can't start with a digit).
#
# Prereq for step 4: a local Postgres is running, e.g.
#   docker run --name pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

set -euo pipefail

DB_NAME=""
DB_PORT=""

fail() { echo "Error: $*" >&2; exit 1; }
set_name() { [ -z "$DB_NAME" ] || fail "More than one database name was given."; DB_NAME="$1"; }
set_port() { [ -z "$DB_PORT" ] || fail "More than one port was given."; DB_PORT="$1"; }

# --- check the arguments before asking for anything ---
for arg in "$@"; do
  case "$arg" in
    --db-name=*) set_name "${arg#*=}" ;;
    --db-port=*) set_port "${arg#*=}" ;;
    # Print only the flag's name: what follows it could be a password.
    -*) fail "Unknown option '${arg%%=*}'. Options: --db-name=<name>, --db-port=<port>. The password is never an argument: setup asks for it (or set PGPASSWORD)." ;;
    ''|*[!0-9]*) set_name "$arg" ;;
    *) set_port "$arg" ;;
  esac
done
# Don't print the value: it could be a password typed in the wrong place.
if [ -n "$DB_NAME" ] && ! printf '%s' "$DB_NAME" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
  fail "That database name isn't valid. Use letters, digits and underscores, starting with a letter or underscore."
fi
DB_PORT="${DB_PORT:-5432}"
if ! printf '%s' "$DB_PORT" | grep -Eq '^[0-9]{1,5}$' || [ "$DB_PORT" -lt 1 ] || [ "$DB_PORT" -gt 65535 ]; then
  fail "That port isn't valid. Use a number from 1 to 65535."
fi

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
if [ -n "${PGPASSWORD:-}" ]; then
  DB_PASSWORD="$PGPASSWORD"
  echo "Using the password from the PGPASSWORD environment variable."
else
  read -r -s -p "Local Postgres password: " DB_PASSWORD; echo
fi
[ -n "$DB_PASSWORD" ] || { echo "Database password is required." >&2; exit 1; }

echo ""
echo "==> [2/5] npm install"
npm install

ENC="$(urlencode "$DB_PASSWORD")"
echo ""
if [ -z "$DB_NAME" ]; then
  DB_NAME="$(SETUP_ADMIN_URL="postgres://postgres:$ENC@localhost:$DB_PORT/postgres" node db/choose-database-name.mjs)" \
    || fail "could not choose a database name - is a local Postgres running on localhost:$DB_PORT, and is the password right?"
fi
echo "==> [3/5] Writing .env (database '$DB_NAME')"
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
