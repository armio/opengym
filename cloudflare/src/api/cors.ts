/** CORS for /api/* (contract §4): only origins listed in APP_ORIGINS are echoed back. */

export function appOrigins(env: Pick<Env, 'APP_ORIGINS'>): Set<string> {
  return new Set(
    (env.APP_ORIGINS ?? '')
      .split(',')
      .map(origin => origin.trim().replace(/\/+$/, '').toLowerCase())
      .filter(Boolean),
  )
}

/** The request's Origin when it is allowed, else null. Requests without Origin (native apps) are not CORS. */
export function allowedOrigin(request: Request, env: Pick<Env, 'APP_ORIGINS'>): string | null {
  const origin = request.headers.get('Origin')
  return origin && appOrigins(env).has(origin.toLowerCase()) ? origin : null
}

export function withCors(response: Response, origin: string | null): Response {
  if (!origin) return response
  const headers = new Headers(response.headers)
  headers.set('Access-Control-Allow-Origin', origin)
  headers.append('Vary', 'Origin')
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers })
}

export function preflightResponse(origin: string | null): Response {
  const headers = new Headers({ Vary: 'Origin' })
  if (origin) {
    headers.set('Access-Control-Allow-Origin', origin)
    headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Timezone')
    headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    headers.set('Access-Control-Max-Age', '86400')
  }
  return new Response(null, { status: 204, headers })
}
