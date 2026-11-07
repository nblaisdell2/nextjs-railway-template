#!/usr/bin/env bash
# One-time personalization after "Use this template" (Bash).
#
#   ./scripts/init-from-template.sh --name my-app \
#       [--repo owner/my-app] [--custom-domain app.example.com]
#
# OFFLINE: it only rewrites files in this repo (no Railway, no network), so you
# can review everything with `git diff` before anything exists in Railway.
#   - replaces the template's placeholder project name in .railway/railway.ts,
#     package.json, package-lock.json, README.md and CLAUDE.md
#   - writes the GitHub repo Railway deploys from into .railway/railway.ts
#   - optionally writes a custom domain into .railway/railway.ts
# Safe to re-run: the --repo / --custom-domain values are (re)written each time.

set -euo pipefail

PROJECT_NAME=""
GITHUB_REPO=""
CUSTOM_DOMAIN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --name)            PROJECT_NAME="$2";  shift 2 ;;
    --repo)            GITHUB_REPO="$2";   shift 2 ;;
    --custom-domain)   CUSTOM_DOMAIN="$2"; shift 2 ;;
    --custom-domain=*) CUSTOM_DOMAIN="${1#*=}"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if ! printf '%s' "$PROJECT_NAME" | grep -Eq '^[a-z][a-z0-9-]{1,28}[a-z0-9]$'; then
  echo "Error: --name must be lowercase letters/digits/hyphens, 3-30 chars, starting with a letter (e.g. 'my-app'). The Railway project is named after it." >&2
  exit 1
fi
if [ -n "$GITHUB_REPO" ] && ! printf '%s' "$GITHUB_REPO" | grep -Eq '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$'; then
  echo "Error: --repo must look like 'owner/repo'." >&2
  exit 1
fi
if [ -n "$CUSTOM_DOMAIN" ]; then
  CUSTOM_DOMAIN="$(printf '%s' "$CUSTOM_DOMAIN" | tr '[:upper:]' '[:lower:]' | sed -E 's#^[[:space:]]+##; s#[[:space:]]+$##; s#^https?://##; s#/.*$##')"
  if ! printf '%s' "$CUSTOM_DOMAIN" | grep -Eq '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$'; then
    echo "Error: --custom-domain must be a hostname like 'app.example.com' (no scheme or path)." >&2
    exit 1
  fi
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$ROOT/.railway/railway.ts"
OLD="nextjs-test"

replace_in() { # from to file
  local p="$ROOT/$3"
  [ -f "$p" ] || return 0
  sed -i.bak "s/$1/$2/g" "$p" && rm -f "$p.bak"
}

set_const() { # name value
  grep -Eq "^[[:space:]]*const[[:space:]]+$1[[:space:]]*=" "$TS" \
    || { echo "Error: could not find 'const $1 = \"...\";' in .railway/railway.ts." >&2; exit 1; }
  sed -i.bak -E "s|^([[:space:]]*const[[:space:]]+$1[[:space:]]*=[[:space:]]*)\"[^\"]*\"([[:space:]]*;)|\1\"$2\"\2|" "$TS" \
    && rm -f "$TS.bak"
}

# 1. Project identity token.
for f in .railway/railway.ts package.json package-lock.json README.md CLAUDE.md; do
  replace_in "$OLD" "$PROJECT_NAME" "$f"
done

# 2. GitHub repo Railway deploys from (deploy-on-push source).
[ -z "$GITHUB_REPO" ] || set_const GITHUB_REPO "$GITHUB_REPO"

# 3. Optional custom domain.
[ -z "$CUSTOM_DOMAIN" ] || set_const CUSTOM_DOMAIN "$CUSTOM_DOMAIN"

REPO_NOW="$(grep -E '^const GITHUB_REPO = ' "$TS" | sed -E 's/^[^"]*"([^"]*)".*/\1/')"
DOMAIN_NOW="$(grep -E '^const CUSTOM_DOMAIN = ' "$TS" | sed -E 's/^[^"]*"([^"]*)".*/\1/')"

echo ""
echo "Personalized to '$PROJECT_NAME'."
echo "  GitHub repo:   $REPO_NOW"
echo "  Custom domain: ${DOMAIN_NOW:-(none - the generated *.up.railway.app domain will be used)}"
case "$REPO_NOW" in
  OWNER/*) echo "  WARNING: GITHUB_REPO is still a placeholder. Re-run with --repo <owner>/<repo>." ;;
esac
echo "Next:"
echo "  1. Review changes:  git diff"
echo "  2. Commit and push to main"
echo "  3. npm run railway:setup"
