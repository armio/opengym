import { HttpError, hasJsonContentType } from '../lib/http'
import { login, logout } from './auth'
import type { ApiContext, DeviceContext, Handler } from './context'
import { allowedOrigin, preflightResponse, withCors } from './cors'
import { authenticateDevice } from './deviceAuth'
import { listDevices, revokeDevice } from './devices'
import { health } from './health'
import { importOpenGym } from './import'
import { revokeAllGrants } from './oauth'
import { resolve, revert } from './proposals'
import { clearRecoveryDays, uploadRecovery } from './recovery'
import { reset } from './reset'
import { pull, pushPull } from './sync'

type Route =
  | { method: 'GET' | 'POST'; path: RegExp; auth: false; handler: Handler<ApiContext> }
  | { method: 'GET' | 'POST'; path: RegExp; auth: true; handler: Handler<DeviceContext> }

const ID = '([A-Za-z0-9_-]{1,64})'

/** Every /api/* endpoint (contract §4). */
const ROUTES: Route[] = [
  { method: 'GET', path: /^\/api\/health$/, auth: false, handler: health },
  { method: 'POST', path: /^\/api\/auth\/login$/, auth: false, handler: login },
  { method: 'POST', path: /^\/api\/auth\/logout$/, auth: true, handler: logout },
  { method: 'GET', path: /^\/api\/devices$/, auth: true, handler: listDevices },
  { method: 'POST', path: new RegExp(`^/api/devices/${ID}/revoke$`), auth: true, handler: revokeDevice },
  { method: 'POST', path: /^\/api\/oauth\/revoke-all$/, auth: true, handler: revokeAllGrants },
  { method: 'GET', path: /^\/api\/sync$/, auth: true, handler: pull },
  { method: 'POST', path: /^\/api\/sync$/, auth: true, handler: pushPull },
  { method: 'POST', path: new RegExp(`^/api/proposals/${ID}/resolve$`), auth: true, handler: resolve },
  { method: 'POST', path: new RegExp(`^/api/proposals/${ID}/revert$`), auth: true, handler: revert },
  { method: 'POST', path: /^\/api\/import\/opengym$/, auth: true, handler: importOpenGym },
  { method: 'POST', path: /^\/api\/reset$/, auth: true, handler: reset },
  { method: 'POST', path: /^\/api\/recovery$/, auth: true, handler: uploadRecovery },
  { method: 'POST', path: /^\/api\/recovery\/clear$/, auth: true, handler: clearRecoveryDays },
]

async function dispatch(request: Request, env: Env, url: URL): Promise<Response> {
  if (url.pathname.startsWith('/api/auth/') && request.headers.has('Origin') && !allowedOrigin(request, env)) {
    throw new HttpError(403, 'Origen no permitido.')
  }
  const candidates = ROUTES.filter(route => route.path.test(url.pathname))
  if (candidates.length === 0) throw new HttpError(404, 'No encontrado.')
  const route = candidates.find(candidate => candidate.method === request.method)
  if (!route) {
    const allow = [...new Set(candidates.map(candidate => candidate.method)), 'OPTIONS'].join(', ')
    throw new HttpError(405, 'Método no permitido.', {}, { Allow: allow })
  }
  if (request.method === 'POST' && !hasJsonContentType(request)) {
    throw new HttpError(415, 'Content-Type debe ser application/json.')
  }
  const context: ApiContext = {
    request,
    env,
    url,
    params: route.path.exec(url.pathname)!.slice(1),
    now: Date.now(),
  }
  if (!route.auth) return route.handler(context)
  return route.handler(await authenticateDevice(context))
}

/** Handles every request under /api/: CORS, content type, device auth, routing and JSON errors. */
export async function handleApi(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url)
  const origin = allowedOrigin(request, env)
  if (request.method === 'OPTIONS') return preflightResponse(origin)
  try {
    return withCors(await dispatch(request, env, url), origin)
  } catch (error) {
    if (error instanceof HttpError) return withCors(error.toResponse(), origin)
    console.error('api error', url.pathname, error)
    return withCors(new HttpError(500, 'Error del servidor.').toResponse(), origin)
  }
}
