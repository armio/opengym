# openGym Worker

The Cloudflare Worker behind the openGym Flutter app: the `/api/*` REST and sync API, the owner
consent page at `/authorize`, and the remote MCP server at `/mcp` that Claude connects to. The
binding contract is [`docs/flutter-cloudflare/ARCHITECTURE.md`](../docs/flutter-cloudflare/ARCHITECTURE.md).

## Layout

| Path | Contents |
|---|---|
| `src/index.ts` | `OAuthProvider` wiring (§5), the MCP handler, the daily cron |
| `src/app.ts` | default handler: `/authorize`, `/api/*`, `/` |
| `src/api/` | REST endpoints (§4): routing, CORS, device auth, sync, proposals, import, reset |
| `src/auth/` | owner password, login/consent rate-limit key, redirect allowlists, consent page |
| `src/db/` | D1 data layer shared with the MCP tools: seq counter, guards, docs, rows, proposals, pull |
| `src/catalog/` | exercise library (`library.json` is generated), custom-exercise merge, search |
| `src/import/` | openGym backup → docs and rows mapping (§4.4) |
| `src/mcp/`, `src/engine/`, `src/coach/` | MCP tools, progression engine, Coach validation |
| `migrations/` | D1 schema (§2.2) |
| `test/` | Vitest in workerd (`@cloudflare/vitest-pool-workers`); `test/helpers.ts` has shared helpers |

## Local development

```sh
npm ci
cp .dev.vars.example .dev.vars      # PUBLIC_ORIGIN=http://localhost:8787 and OWNER_PASSWORD
npm run db:migrate:local
npm run dev                         # http://localhost:8787/api/health
```

The Claude connector URL is `${PUBLIC_ORIGIN}/mcp`. Protected resource metadata is served at
`/.well-known/oauth-protected-resource/mcp` (RFC 9728 path form; the bare
`/.well-known/oauth-protected-resource` is 404 by design of the OAuth library).

## Deploy

```sh
npx wrangler d1 create opengym-db              # copy the id into wrangler.jsonc
npx wrangler kv namespace create OAUTH_KV      # copy the id into wrangler.jsonc
# set vars.PUBLIC_ORIGIN in wrangler.jsonc to the Worker's public origin
npx wrangler secret put OWNER_PASSWORD         # at least 12 characters
npm run db:migrate:remote
npm run deploy
```

## Checks

```sh
npm run check                                  # typecheck + tests
npx wrangler deploy --dry-run --outdir /tmp/opengym-build
```
