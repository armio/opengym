import { AuthorizationError, CimdFetchError, type AuthRequest, type ConsentDescription } from '@cloudflare/workers-oauth-provider'
import { clearAuthAttempt, recordAuthAttempt } from '../db/authFailures'
import { clientKey } from './clientKey'
import { renderConsentPage, renderMessagePage } from './consentPage'
import { isOwnerPassword, MISCONFIGURED_PASSWORD_MESSAGE, ownerPasswordConfigured } from './password'
import { extraRedirectHosts, isAllowedRegistrationRedirect } from './redirects'

/** The single subject every grant is issued to; tools never read it (contract §5). */
export const OWNER_USER_ID = 'owner'
export const MCP_SCOPES = ['mcp']

/**
 * Headers for every page this endpoint renders. `form-action` also names the client's redirect
 * origin because Chrome applies it to the redirect that follows the form submission.
 */
function pageHeaders(base: HeadersInit | undefined, redirectUri?: string): Headers {
  const headers = new Headers(base)
  let formAction = "'self'"
  if (redirectUri) {
    try {
      formAction += ` ${new URL(redirectUri).origin}`
    } catch {
      // parseAuthRequest already validated it; a malformed value just keeps 'self' only.
    }
  }
  headers.set(
    'Content-Security-Policy',
    `default-src 'none'; style-src 'unsafe-inline'; form-action ${formAction}; frame-ancestors 'none'; base-uri 'none'`,
  )
  headers.set('X-Frame-Options', 'DENY')
  headers.set('X-Content-Type-Options', 'nosniff')
  headers.set('Referrer-Policy', 'no-referrer')
  headers.set('Cache-Control', 'no-store')
  headers.set('Content-Type', 'text/html; charset=utf-8')
  return headers
}

function messagePage(status: number, title: string, message: string): Response {
  return new Response(renderMessagePage(title, message), { status, headers: pageHeaders(undefined) })
}

function consentPage(status: number, details: ConsentDescription, handle: string, base?: HeadersInit, error?: string): Response {
  return new Response(renderConsentPage({ details, handle, error }), {
    status,
    headers: pageHeaders(base, details.redirectUri),
  })
}

const restart = 'Vuelve a conectar openGym desde Claude para empezar de nuevo.'

/**
 * Maps the library's expected failures to a local page or, when it is safe, a redirect
 * (docs/consent-page.md). Only allowlisted redirect URIs are followed: a client identified by a
 * metadata document (CIMD) never passes through the registration allowlist, so without this check
 * /authorize would bounce anyone to a URI of the attacker's choosing.
 */
function authorizationFailure(error: unknown, env: Env): Response {
  if (error instanceof AuthorizationError && error.redirectTo && error.redirectUri && isAllowedRegistrationRedirect(error.redirectUri, extraRedirectHosts(env))) {
    return Response.redirect(error.redirectTo, 302)
  }
  if (error instanceof AuthorizationError) return messagePage(400, 'No se puede autorizar', `${error.description}. ${restart}`)
  if (error instanceof CimdFetchError) return messagePage(400, 'No se puede autorizar', 'No se pudo verificar esta aplicación.')
  throw error
}

async function describeAllowed(env: Env, authRequest: AuthRequest): Promise<ConsentDescription | Response> {
  const details = await env.OAUTH_PROVIDER.describeConsent(authRequest)
  // The full URI, not just the host: CIMD clients skip the registration allowlist, so this is
  // where their redirect is held to the same rule (Claude's exact callbacks, loopback /callback).
  if (!isAllowedRegistrationRedirect(details.redirectUri, extraRedirectHosts(env))) {
    return messagePage(403, 'Destino no permitido', `openGym no envía accesos a ${details.redirectHost}.`)
  }
  return details
}

async function showConsent(request: Request, env: Env): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER
  const authRequest = await oauth.parseAuthRequest(request)
  const details = await describeAllowed(env, authRequest)
  if (details instanceof Response) return details
  if (!ownerPasswordConfigured(env)) return messagePage(500, 'Servidor mal configurado', MISCONFIGURED_PASSWORD_MESSAGE)
  const consent = await oauth.beginConsent(authRequest)
  return consentPage(200, details, consent.handle, consent.headers)
}

/** Re-renders the page for the same, still unused handle after a wrong password. */
async function rejectPassword(request: Request, env: Env, handle: string): Promise<Response> {
  const error = 'Contraseña incorrecta.'
  try {
    const details = await describeAllowed(env, await env.OAUTH_PROVIDER.parseAuthRequest(request))
    if (details instanceof Response) return details
    return consentPage(401, details, handle, undefined, error)
  } catch (failure) {
    if (failure instanceof AuthorizationError || failure instanceof CimdFetchError) return messagePage(401, error, restart)
    throw failure
  }
}

async function submitConsent(request: Request, env: Env, now: number): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER
  const form = await request.formData()
  const handle = String(form.get('handle') ?? '')

  if (form.get('decision') !== 'approve') {
    const denied = await oauth.denyConsent(request, handle)
    return new Response(null, { status: 302, headers: denied.headers })
  }
  if (!ownerPasswordConfigured(env)) return messagePage(500, 'Servidor mal configurado', MISCONFIGURED_PASSWORD_MESSAGE)

  const attempt = await recordAuthAttempt(env.DB, clientKey(request), now)
  if (attempt.limited) return messagePage(429, 'Demasiados intentos', 'Espera unos minutos y vuelve a intentarlo.')
  if (!(await isOwnerPassword(env, String(form.get('password') ?? '')))) return rejectPassword(request, env, handle)
  await clearAuthAttempt(env.DB, attempt.id)

  // Consent is never remembered: every authorization shows this page again.
  const approved = await oauth.approveConsent(request, handle, { scope: MCP_SCOPES })
  const { redirectTo } = await oauth.completeAuthorization({
    request: approved.request,
    userId: OWNER_USER_ID,
    metadata: {},
    scope: MCP_SCOPES,
    props: { owner: true },
  })
  approved.headers.set('Location', redirectTo)
  return new Response(null, { status: 302, headers: approved.headers })
}

/** `GET|POST /authorize`: the owner-password consent page (contract §5). */
export async function handleAuthorize(request: Request, env: Env): Promise<Response> {
  try {
    if (request.method === 'GET') return await showConsent(request, env)
    if (request.method === 'POST') return await submitConsent(request, env, Date.now())
  } catch (error) {
    return authorizationFailure(error, env)
  }
  return new Response(null, { status: 405, headers: { Allow: 'GET, POST' } })
}
