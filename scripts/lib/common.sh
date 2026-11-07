#!/usr/bin/env bash
# Shared helpers, sourced by the railway-* Bash scripts:
#   . "$(dirname "$0")/lib/common.sh"
# Keep in sync with scripts/lib/common.ps1.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAILWAY_TS="$ROOT/.railway/railway.ts"
WEB_SERVICE="web"        # service names declared in .railway/railway.ts
DB_SERVICE="postgres"

step() { # n total label
  echo ""
  echo "==> [$1/$2] $3"
}

die() { echo "Error: $*" >&2; exit 1; }

is_interactive() { [ -t 0 ]; }

# Read a `const NAME = "value";` line from .railway/railway.ts.
get_railway_const() {
  [ -f "$RAILWAY_TS" ] || die ".railway/railway.ts not found."
  local line
  line="$(grep -E "^[[:space:]]*const[[:space:]]+$1[[:space:]]*=[[:space:]]*\"[^\"]*\"[[:space:]]*;" "$RAILWAY_TS" | head -1)" \
    || die "Could not find 'const $1 = \"...\";' in .railway/railway.ts."
  printf '%s' "$line" | sed -E 's/^[^"]*"([^"]*)".*/\1/'
}

# Rewrite a `const NAME = "value";` line in .railway/railway.ts.
set_railway_const() { # name value
  grep -Eq "^[[:space:]]*const[[:space:]]+$1[[:space:]]*=" "$RAILWAY_TS" \
    || die "Could not find 'const $1 = \"...\";' in .railway/railway.ts."
  sed -i.bak -E "s|^([[:space:]]*const[[:space:]]+$1[[:space:]]*=[[:space:]]*)\"[^\"]*\"([[:space:]]*;)|\1\"$2\"\2|" "$RAILWAY_TS" \
    && rm -f "$RAILWAY_TS.bak"
}

assert_railway_cli() {
  command -v railway >/dev/null 2>&1 \
    || die "Railway CLI not found. Install it with 'npm install -g @railway/cli' (see https://docs.railway.com/cli)."
}

assert_railway_login() {
  railway whoami >/dev/null 2>&1 || die "Not logged in to Railway. Run 'railway login' first."
}

is_railway_linked() { railway status --json >/dev/null 2>&1; }

assert_railway_linked() {
  is_railway_linked \
    || die "This folder isn't linked to a Railway project. Run 'npm run railway:setup' first (or 'railway link')."
}

# Read one field from JSON on stdin, using node (always present here).
json_field() { # dotted.path
  node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      try {
        let v = JSON.parse(s);
        for (const k of process.argv[1].split(".")) v = v == null ? undefined : v[k];
        process.stdout.write(v == null ? "" : String(v));
      } catch { process.stdout.write(""); }
    });' "$1"
}

# The web service's Railway-provided domain (e.g. my-app.up.railway.app), or "".
get_railway_domain() {
  railway variables --service "$WEB_SERVICE" --json 2>/dev/null | json_field RAILWAY_PUBLIC_DOMAIN || true
}
