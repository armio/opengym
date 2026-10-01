#!/usr/bin/env bash
# Deploys the Worker to its custom domain and sets the owner password, then smoke-tests it.
#
#   CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… OPENGYM_OWNER_PASSWORD=… scripts/deploy.sh [--set-password]
#
# The token needs Workers Scripts Edit/Admin on the account and Workers Routes Edit on the zone of
# the custom domain (armio.cc); D1 Edit as well for `migrations apply`. OPENGYM_OWNER_PASSWORD
# becomes the OWNER_PASSWORD secret (app login and Claude consent) on the first deploy, or with
# --set-password; a redeploy keeps the current one (it may have been changed in the dashboard).
# The smoke test logs in with it either way. It is never printed.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN (a Cloudflare API token that can deploy Workers)}"
: "${CLOUDFLARE_ACCOUNT_ID:?set CLOUDFLARE_ACCOUNT_ID}"
: "${OPENGYM_OWNER_PASSWORD:?set OPENGYM_OWNER_PASSWORD (at least 12 characters)}"
if [ "${#OPENGYM_OWNER_PASSWORD}" -lt 12 ]; then
  echo "OPENGYM_OWNER_PASSWORD must have at least 12 characters" >&2
  exit 1
fi

origin=$(grep -o '"PUBLIC_ORIGIN": *"[^"]*"' wrangler.jsonc | sed 's/.*"\(http[^"]*\)"$/\1/')
echo "Deploying openGym to ${origin}"

npm ci
npm run typecheck
npx wrangler d1 migrations apply opengym-db --remote   # no-op when the schema is current
npx wrangler deploy
# Listing must succeed: a failure here must not fall through to overwriting the password.
secrets=$(npx wrangler secret list --format json)
if [ "${1:-}" = "--set-password" ] || ! grep -q '"OWNER_PASSWORD"' <<<"$secrets"; then
  printf '%s' "$OPENGYM_OWNER_PASSWORD" | npx wrangler secret put OWNER_PASSWORD
else
  echo "OWNER_PASSWORD is already set; keeping it (pass --set-password to replace it)."
fi

# A new custom domain can take a minute to get its certificate.
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl -fsS "${origin}/api/health" >/dev/null 2>&1; then break; fi
  echo "waiting for ${origin} (${attempt})…"
  sleep 10
done
node scripts/smoke.mjs --origin "$origin"
echo
echo "Claude connector URL: ${origin}/mcp"
