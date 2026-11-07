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

# `railway config <plan|apply> ...`, with a Windows (Git Bash) workaround: the
# `railway/iac` package checks the CLI version by spawning $_ (bash sets it to
# the command's path) without a shell, which can't run npm's railway shim.
# Calling the real railway.exe that the npm package ships makes $_ point at it.
railway_config() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if ! command -v railway.exe >/dev/null 2>&1; then
        local exe
        exe="$(npm root -g 2>/dev/null)/@railway/cli/bin/railway.exe"
        if [ -f "$exe" ]; then "$exe" config "$@"; return; fi
      fi ;;
  esac
  railway config "$@"
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

# "<id> <status>" of the web service's latest deployment, or "".
latest_deployment() {
  railway deployment list --service "$WEB_SERVICE" --limit 1 --json 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      try {
        let j = JSON.parse(s);
        if (Array.isArray(j)) j = j[0];
        process.stdout.write(j && j.id ? `${j.id} ${j.status || ""}` : "");
      } catch { process.stdout.write(""); }
    });' || true
}

# Wait until the web service's latest deployment (newer than $1, if given) is
# SUCCESS. Dies on FAILED/CRASHED, if none starts within 3 minutes, or after
# 20 minutes. $2 = hint printed when no deploy starts.
wait_for_deploy() { # [after_id] [no_start_hint]
  local after="${1:-}" hint="${2:-}" start last="" dep id status elapsed
  start=$(date +%s)
  while true; do
    dep="$(latest_deployment)"
    id="${dep%% *}"; status="${dep#* }"
    if [ -z "$dep" ] || { [ -n "$after" ] && [ "$id" = "$after" ]; }; then status=""; fi
    if [ "$status" != "$last" ]; then
      echo "  $(date +%H:%M:%S)  ${status:-waiting for Railway to start a deploy...}"
      last="$status"
    fi
    case "$status" in
      SUCCESS) return 0 ;;
      FAILED|CRASHED)
        die "The deploy $status. See the logs: 'railway logs --service $WEB_SERVICE --build' (build) or 'railway logs --service $WEB_SERVICE' (runtime / pre-deploy migrations)." ;;
    esac
    elapsed=$(( $(date +%s) - start ))
    if [ -z "$status" ] && [ "$elapsed" -gt 180 ]; then die "No deploy started. $hint"; fi
    [ "$elapsed" -le 1200 ] || die "Timed out waiting for the deploy. Check 'railway logs --service $WEB_SERVICE' or the dashboard ('railway open')."
    sleep 10
  done
}

# Domain names attached to the web service (generated and custom), one per line.
railway_domain_names() {
  railway domain list --service "$WEB_SERVICE" --json 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      try { for (const d of JSON.parse(s).domains || []) console.log(d.domain); } catch {}
    });' || true
}

# Attach a custom domain to the web service if it isn't already, then print
# its status and the DNS records to add (CNAME + TXT).
add_custom_domain() { # domain
  local domain="$1"
  if railway_domain_names | grep -qxF "$domain"; then
    echo "$domain is already attached to '$WEB_SERVICE'."
  else
    railway domain "$domain" --service "$WEB_SERVICE" >/dev/null 2>&1 || true
    # The domain list can lag a few seconds behind the create.
    local i attached=false
    for i in 1 2 3 4 5; do
      if railway_domain_names | grep -qxF "$domain"; then attached=true; break; fi
      sleep 3
    done
    [ "$attached" = true ] || die "Could not attach $domain (is it already used by another Railway service?)."
    echo "Attached $domain to '$WEB_SERVICE'."
  fi
  railway domain status "$domain" --service "$WEB_SERVICE" || true
  echo ""
  echo "Add BOTH DNS records above at your DNS provider:"
  echo "  - the CNAME routes traffic to Railway"
  echo "  - the TXT (_railway-verify...) proves you own the domain; without it Railway answers 404"
  echo "Using Cloudflare? Keep these records DNS-only (grey cloud) at least until the certificate is"
  echo "issued, and nested subdomains (a.b.example.com) need DNS-only unless you have Advanced Certificate Manager."
  echo "Railway issues the HTTPS certificate automatically once DNS propagates. Check with:"
  echo "  railway domain status $domain --service $WEB_SERVICE"
}

# The web service's Railway-provided domain (e.g. my-app.up.railway.app), or "".
# (Not RAILWAY_PUBLIC_DOMAIN: that switches to the custom domain once one exists.)
get_railway_domain() {
  railway domain list --service "$WEB_SERVICE" --json 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      try {
        const d = (JSON.parse(s).domains || []).find(x => x.type === "service");
        process.stdout.write(d ? d.domain : "");
      } catch {}
    });' || true
}
