import { handleApi } from './api/router'
import { handleAuthorize } from './auth/consent'

/**
 * The default handler behind OAuthProvider: everything that is not an OAuth protocol endpoint or
 * the protected /mcp route.
 */
export const app: ExportedHandler<Env> = {
  async fetch(request, env) {
    const { pathname } = new URL(request.url)
    if (pathname === '/authorize') return handleAuthorize(request, env)
    if (pathname === '/api' || pathname.startsWith('/api/')) return handleApi(request, env)
    if (pathname === '/') {
      return new Response(`openGym está funcionando.\nURL del conector de Claude: ${env.PUBLIC_ORIGIN}/mcp\n`, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
      })
    }
    return new Response('No encontrado.\n', { status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' } })
  },
}
