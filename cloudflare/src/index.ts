import { OAuthProvider, type ClientRegistrationCallbackOptions, type ClientRegistrationCallbackResult } from '@cloudflare/workers-oauth-provider'
import { createMcpHandler } from 'agents/mcp/server'
import { env as workerEnv } from 'cloudflare:workers'
import { app } from './app'
import { MCP_SCOPES } from './auth/consent'
import { extraRedirectHosts, isAllowedRegistrationRedirect } from './auth/redirects'
import { runDailyCleanup } from './cron'
import { createServer } from './mcp/server'

const ACCESS_TOKEN_TTL = 3600
const REFRESH_TOKEN_TTL = 30 * 24 * 3600

/** Dynamic client registration accepts only clients whose redirect URIs all go to Claude or a loopback callback (contract §5). */
function claudeRedirectsOnly({ clientMetadata }: ClientRegistrationCallbackOptions): ClientRegistrationCallbackResult | void {
  const uris = clientMetadata.redirect_uris
  const hosts = extraRedirectHosts(workerEnv)
  const allowed =
    Array.isArray(uris) && uris.length > 0 && uris.every(uri => typeof uri === 'string' && isAllowedRegistrationRedirect(uri, hosts))
  if (!allowed) {
    return {
      code: 'access_denied',
      description: 'openGym only accepts clients that redirect to Claude or to a local callback.',
      status: 403,
    }
  }
}

function createProvider(origin: string): OAuthProvider<Env> {
  const host = new URL(origin).hostname
  const mcpHandler = createMcpHandler(() => createServer(workerEnv), {
    route: '/mcp',
    allowedHostnames: [host],
    // Requests without an Origin header (non-browser MCP clients) stay valid.
    allowedOriginHostnames: [host, 'claude.ai', 'claude.com'],
  })
  return new OAuthProvider<Env>({
    apiRoute: '/mcp',
    // The handler is a plain function; OAuthProvider expects an object with fetch.
    apiHandler: { fetch: (request, env, ctx) => mcpHandler(request, env, ctx) },
    defaultHandler: app,
    authorizeEndpoint: '/authorize',
    tokenEndpoint: '/token',
    clientRegistrationEndpoint: '/register',
    resourceMetadata: { resource: `${origin}/mcp`, resource_name: 'openGym' },
    scopesSupported: MCP_SCOPES,
    requiredScopes: MCP_SCOPES,
    accessTokenTTL: ACCESS_TOKEN_TTL,
    refreshTokenTTL: REFRESH_TOKEN_TTL,
    refreshTokenIdleTTL: REFRESH_TOKEN_TTL,
    clientIdMetadataDocumentEnabled: true,
    clientRegistrationCallback: claudeRedirectsOnly,
  })
}

class ConfigurationError extends Error {}

/** PUBLIC_ORIGIN must be exactly an origin: scheme and lowercase host, optional port, no path or trailing slash. */
function publicOrigin(env: Env): string {
  const origin = env.PUBLIC_ORIGIN ?? ''
  let parsed: URL | undefined
  try {
    parsed = new URL(origin)
  } catch {
    // reported below
  }
  if (!parsed || parsed.origin !== origin || (parsed.protocol !== 'https:' && parsed.protocol !== 'http:')) {
    throw new ConfigurationError(
      `Servidor mal configurado: PUBLIC_ORIGIN debe ser un origen sin barra final, p. ej. https://opengym.example.workers.dev (ahora: "${origin}")`,
    )
  }
  return origin
}

let cached: { origin: string; provider: OAuthProvider<Env> } | undefined

/** One provider per isolate, rebuilt only if PUBLIC_ORIGIN changes (it fixes the token audience). */
function providerFor(env: Env): OAuthProvider<Env> {
  const origin = publicOrigin(env)
  if (cached?.origin !== origin) cached = { origin, provider: createProvider(origin) }
  return cached.provider
}

export default {
  async fetch(request, env, ctx) {
    let provider: OAuthProvider<Env>
    try {
      provider = providerFor(env)
    } catch (error) {
      if (!(error instanceof ConfigurationError)) throw error
      return Response.json({ error: error.message }, { status: 500, headers: { 'Cache-Control': 'no-store' } })
    }
    return provider.fetch(request, env, ctx)
  },

  async scheduled(_controller, env) {
    await runDailyCleanup(providerFor(env), env)
  },
} satisfies ExportedHandler<Env>
