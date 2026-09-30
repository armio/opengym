import type { OAuthHelpers } from '@cloudflare/workers-oauth-provider'

declare global {
  namespace Cloudflare {
    interface Env {
      DB: D1Database
      OAUTH_KV: KVNamespace
      /** The one public origin, e.g. https://opengym.example.workers.dev (no trailing slash). */
      PUBLIC_ORIGIN: string
      /** Comma-separated browser origins allowed to call /api/*. */
      APP_ORIGINS: string
      /** Comma-separated extra OAuth redirect hostnames. */
      ALLOWED_REDIRECT_HOSTS: string
      /** Secret shared by device login and the MCP consent page (≥ 12 characters). */
      OWNER_PASSWORD?: string
      /** Injected by OAuthProvider into requests it routes to the default handler. */
      OAUTH_PROVIDER: OAuthHelpers
    }
  }
  interface Env extends Cloudflare.Env {}
}

export {}
