#!/usr/bin/env bash
# Generate the Railway domain, or attach a custom domain (Bash).
#   ./scripts/railway-domain.sh                     -> generated *.up.railway.app domain
#   ./scripts/railway-domain.sh app.example.com     -> custom domain   [--yes]
#
# Custom domain: the domain is written into CUSTOM_DOMAIN in .railway/railway.ts
# and attached with `railway config apply`, so the file stays the source of
# truth (a domain added only with `railway domain <d>` would be REMOVED by the
# next `railway config apply`). Then it prints the DNS records to add at your
# DNS provider: a CNAME (where traffic goes) AND a TXT (proves you own the
# domain; without it Railway answers 404). Railway issues the Let's Encrypt
# certificate automatically once DNS has propagated.

set -euo pipefail

DOMAIN=""
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    -*) echo "Unknown arg: $arg" >&2; exit 1 ;;
    *) [ -z "$DOMAIN" ] || { echo "Only one domain at a time." >&2; exit 1; }; DOMAIN="$arg" ;;
  esac
done

. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
cd "$ROOT"

if [ -z "$DOMAIN" ]; then
  TOTAL=2
  step 1 $TOTAL "Checking Railway CLI + linked project"
  assert_railway_cli; assert_railway_login; assert_railway_linked

  step 2 $TOTAL "Railway-provided domain for '$WEB_SERVICE'"
  EXISTING="$(get_railway_domain)"
  if [ -n "$EXISTING" ]; then
    echo "Already has one: https://$EXISTING"
    exit 0
  fi
  railway domain --service "$WEB_SERVICE" || die "railway domain failed"
  D="$(get_railway_domain)"
  [ -z "$D" ] || { echo ""; echo "Live at:  https://$D"; }
  exit 0
fi

DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | sed -E 's#^https?://##; s#/.*$##')"
printf '%s' "$DOMAIN" | grep -Eq '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$' \
  || die "'$DOMAIN' doesn't look like a hostname (e.g. app.example.com)."
TOTAL=4

step 1 $TOTAL "Checking Railway CLI + linked project"
assert_railway_cli; assert_railway_login; assert_railway_linked

step 2 $TOTAL "Writing CUSTOM_DOMAIN = \"$DOMAIN\" into .railway/railway.ts"
PREVIOUS="$(get_railway_const CUSTOM_DOMAIN)"
if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "$DOMAIN" ]; then
  echo "Replacing the previous custom domain '$PREVIOUS' (it will be detached)."
fi
set_railway_const CUSTOM_DOMAIN "$DOMAIN"

step 3 $TOTAL "railway config plan / apply"
railway config plan || die "railway config plan failed"
APPLY_ARGS=()
[ "$ASSUME_YES" = true ] && APPLY_ARGS+=(--yes)
railway config apply ${APPLY_ARGS[@]+"${APPLY_ARGS[@]}"} \
  || die "railway config apply failed (or was declined). .railway/railway.ts was already edited; revert with 'git checkout .railway/railway.ts' if needed."

step 4 $TOTAL "DNS records for $DOMAIN"
railway domain status "$DOMAIN" --service "$WEB_SERVICE" || die "railway domain status failed"

echo ""
echo "Add BOTH records above at your DNS provider:"
echo "  - CNAME  $DOMAIN -> the Railway target shown above (routes the traffic)"
echo "  - TXT    the verification record shown above (proves ownership; missing TXT = 404)"
echo "Using Cloudflare? Keep '_acme-challenge' records DNS-only, and nested subdomains"
echo "(a.b.example.com) DNS-only (grey cloud) unless you have Advanced Certificate Manager."
echo "Railway issues the HTTPS certificate once DNS propagates. Check progress with:"
echo "  railway domain status $DOMAIN --service $WEB_SERVICE"
echo "Commit .railway/railway.ts so the domain stays declared."
