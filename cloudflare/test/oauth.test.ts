import { getOAuthApi } from '@cloudflare/workers-oauth-provider'
import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import {
  CLAUDE_CALLBACK,
  MCP_INITIALIZE,
  ORIGIN,
  PASSWORD,
  api,
  consentForm,
  exchangeCode,
  fetchWorker,
  getAccessToken,
  loginDevice,
  mcpCall,
  registerClient,
  resetDatabase,
  startAuthorization,
  submitConsent,
} from './helpers'

beforeEach(resetDatabase)

describe('discovery', () => {
  it('publishes protected resource metadata for the /mcp resource', async () => {
    const response = await fetchWorker('/.well-known/oauth-protected-resource/mcp')
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual(
      expect.objectContaining({ resource: `${ORIGIN}/mcp`, authorization_servers: [ORIGIN], scopes_supported: ['mcp'], resource_name: 'openGym' }),
    )
  })

  it('publishes authorization server metadata', async () => {
    const metadata = (await (await fetchWorker('/.well-known/oauth-authorization-server')).json()) as Record<string, unknown>
    expect(metadata).toEqual(
      expect.objectContaining({
        issuer: ORIGIN,
        authorization_endpoint: `${ORIGIN}/authorize`,
        token_endpoint: `${ORIGIN}/token`,
        registration_endpoint: `${ORIGIN}/register`,
        scopes_supported: ['mcp'],
        client_id_metadata_document_supported: true,
      }),
    )
  })

  it('challenges /mcp without a token with a 401 that points at the resource metadata', async () => {
    const { status, headers } = await mcpCall(null, 'initialize', MCP_INITIALIZE)
    expect(status).toBe(401)
    const challenge = headers.get('WWW-Authenticate') ?? ''
    expect(challenge).toMatch(/^Bearer /)
    expect(challenge).toContain(`resource_metadata="${ORIGIN}/.well-known/oauth-protected-resource/mcp"`)
    expect(challenge).toContain('scope="mcp"')
  })
})

describe('client registration', () => {
  it('accepts Claude and loopback callbacks', async () => {
    for (const uris of [[CLAUDE_CALLBACK], ['https://claude.com/api/mcp/auth_callback', 'http://localhost:33418/callback'], ['http://127.0.0.1:5173/callback'], ['https://partner.example.com/oauth/cb']]) {
      const response = await registerClient(uris)
      expect(response.status, uris.join()).toBe(201)
    }
  })

  it('rejects any foreign redirect with 403 access_denied', async () => {
    for (const uris of [['https://evil.example/callback'], [CLAUDE_CALLBACK, 'https://evil.example/cb'], ['http://localhost:8080/other'], ['https://claude.ai/elsewhere']]) {
      const response = await registerClient(uris)
      expect(response.status, uris.join()).toBe(403)
      expect(await response.json()).toEqual(expect.objectContaining({ error: 'access_denied' }))
    }
  })
})

describe('consent page', () => {
  it('renders the client and redirect host escaped, with the security headers', async () => {
    const registered = (await (
      await fetchWorker('/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ client_name: '<script>alert(1)</script>', redirect_uris: [CLAUDE_CALLBACK], token_endpoint_auth_method: 'none' }),
      })
    ).json()) as { client_id: string }
    const session = await startAuthorization(registered.client_id)
    const page = await fetchWorker(session.authorizeUrl)
    expect(page.status).toBe(200)
    expect(page.headers.get('Content-Security-Policy')).toBe(
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https://claude.ai; frame-ancestors 'none'; base-uri 'none'",
    )
    expect(page.headers.get('X-Frame-Options')).toBe('DENY')
    expect(page.headers.get('Cache-Control')).toBe('no-store')
    expect(page.headers.get('Set-Cookie')).toMatch(/^__Host-oauth-consent-/)
    const html = await page.text()
    expect(html).not.toContain('<script>')
    expect(html).toContain('&#60;script&#62;alert(1)&#60;/script&#62;')
    expect(html).toContain('<strong>claude.ai</strong>')
    expect(html).toContain('Permitir')
    expect(html).toContain('Denegar')
    expect(html).not.toContain('aplicación de este ordenador')
  })

  it('warns about loopback redirects', async () => {
    const client = (await (await registerClient(['http://localhost:33418/callback'])).json()) as { client_id: string }
    const params = new URLSearchParams({
      response_type: 'code', client_id: client.client_id, redirect_uri: 'http://localhost:33418/callback', scope: 'mcp',
      state: 's', code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM', code_challenge_method: 'S256',
    })
    const html = await (await fetchWorker(`/authorize?${params}`)).text()
    expect(html).toContain('aplicación de este ordenador')
  })

  it('renders invalid requests locally instead of redirecting', async () => {
    const response = await fetchWorker('/authorize?client_id=unknown&redirect_uri=https://evil.example/cb&response_type=code', { redirect: 'manual' })
    expect(response.status).toBe(400)
    expect(response.headers.get('Location')).toBeNull()
    expect(response.headers.get('X-Frame-Options')).toBe('DENY')
  })

  it('re-renders with the same handle on a wrong password, then approves', async () => {
    const session = await startAuthorization()
    const { handle, cookie } = await consentForm(await fetchWorker(session.authorizeUrl))

    const wrong = await submitConsent(session.authorizeUrl, { handle, password: 'not the password', decision: 'approve' }, cookie)
    expect(wrong.status).toBe(401)
    const html = await wrong.text()
    expect(html).toContain('Contraseña incorrecta.')
    expect(html).toContain(`name="handle" value="${handle}"`)
    expect(wrong.headers.get('X-Frame-Options')).toBe('DENY')

    const approved = await submitConsent(session.authorizeUrl, { handle, password: PASSWORD, decision: 'approve' }, cookie)
    expect(approved.status).toBe(302)
    const location = new URL(approved.headers.get('Location')!)
    expect(`${location.origin}${location.pathname}`).toBe(CLAUDE_CALLBACK)
    expect(location.searchParams.get('state')).toBe(session.state)
    expect(location.searchParams.get('iss')).toBe(ORIGIN)
    expect(location.searchParams.get('code')).toBeTruthy()

    // The handle works once.
    const replay = await submitConsent(session.authorizeUrl, { handle, password: PASSWORD, decision: 'approve' }, cookie)
    expect(replay.status).toBe(400)
  })

  it('needs the browser binding cookie', async () => {
    const session = await startAuthorization()
    const { handle } = await consentForm(await fetchWorker(session.authorizeUrl))
    const response = await submitConsent(session.authorizeUrl, { handle, password: PASSWORD, decision: 'approve' }, '')
    expect(response.status).toBe(400)
  })

  it('redirects with access_denied when the owner denies', async () => {
    const session = await startAuthorization()
    const { handle, cookie } = await consentForm(await fetchWorker(session.authorizeUrl))
    const denied = await submitConsent(session.authorizeUrl, { handle, decision: 'deny' }, cookie)
    expect(denied.status).toBe(302)
    const location = new URL(denied.headers.get('Location')!)
    expect(location.searchParams.get('error')).toBe('access_denied')
    expect(location.searchParams.get('state')).toBe(session.state)
  })

  it('refuses redirect hosts outside the allowlist, even for CIMD-style clients', async () => {
    // Created through the helper API, bypassing the registration allowlist (as a CIMD client would).
    const oauth = getOAuthApi(
      {
        apiRoute: '/mcp',
        apiHandler: { fetch: () => new Response() },
        defaultHandler: { fetch: () => new Response() },
        authorizeEndpoint: '/authorize',
        tokenEndpoint: '/token',
        resourceMetadata: { resource: `${ORIGIN}/mcp` },
      },
      env,
    )
    const { clientId } = await oauth.createClient({ redirectUris: ['https://evil.example/cb'], clientName: 'Evil', tokenEndpointAuthMethod: 'none' })
    const params = new URLSearchParams({
      response_type: 'code', client_id: clientId, redirect_uri: 'https://evil.example/cb', scope: 'mcp',
      state: 's', code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM', code_challenge_method: 'S256',
    })
    const response = await fetchWorker(`/authorize?${params}`, { redirect: 'manual' })
    expect(response.status).toBe(403)
    expect(response.headers.get('Set-Cookie')).toBeNull()
  })

  it('shares the login rate limit', async () => {
    const session = await startAuthorization()
    const { handle, cookie } = await consentForm(await fetchWorker(session.authorizeUrl))
    const headers = { 'CF-Connecting-IP': '203.0.113.99' }
    for (let i = 0; i < 10; i++) await api('/api/auth/login', { body: { password: 'wrong password!' }, headers })
    const response = await fetchWorker(session.authorizeUrl, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/x-www-form-urlencoded', Cookie: cookie },
      body: new URLSearchParams({ handle, password: PASSWORD, decision: 'approve' }).toString(),
      redirect: 'manual',
    })
    expect(response.status).toBe(429)
  })
})

describe('token exchange and /mcp', () => {
  it('exchanges the code with PKCE and serves MCP with the access token', async () => {
    const session = await startAuthorization()
    const { handle, cookie } = await consentForm(await fetchWorker(session.authorizeUrl))
    const approved = await submitConsent(session.authorizeUrl, { handle, password: PASSWORD, decision: 'approve' }, cookie)
    const code = new URL(approved.headers.get('Location')!).searchParams.get('code')!

    const badVerifier = await exchangeCode({ ...session, verifier: 'x'.repeat(43) }, code)
    expect(badVerifier.status).toBe(400)

    const session2 = await startAuthorization(session.clientId)
    const form2 = await consentForm(await fetchWorker(session2.authorizeUrl))
    const approved2 = await submitConsent(session2.authorizeUrl, { handle: form2.handle, password: PASSWORD, decision: 'approve' }, form2.cookie)
    const code2 = new URL(approved2.headers.get('Location')!).searchParams.get('code')!
    const tokenResponse = await exchangeCode(session2, code2)
    expect(tokenResponse.status).toBe(200)
    const tokens = (await tokenResponse.json()) as Record<string, unknown>
    expect(tokens).toEqual(
      expect.objectContaining({ token_type: 'bearer', expires_in: 3600, scope: 'mcp', resource: `${ORIGIN}/mcp`, refresh_token: expect.any(String) }),
    )
    const token = tokens.access_token as string

    const init = await mcpCall(token, 'initialize', MCP_INITIALIZE)
    expect(init.status).toBe(200)
    expect(init.message.result.serverInfo.name).toBe('opengym')

    const tools = await mcpCall(token, 'tools/list', {}, 2)
    expect(tools.status).toBe(200)
    expect(tools.message.result.tools.map((tool: { name: string }) => tool.name)).toContain('get_overview')

    const overview = await mcpCall(token, 'tools/call', { name: 'get_overview', arguments: {} }, 3)
    expect(overview.status).toBe(200)
    expect(overview.message.result.isError ?? false).toBe(false)
  })

  it('rejects requests from a foreign browser origin', async () => {
    const token = await getAccessToken()
    const response = await fetchWorker('/mcp', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        Origin: 'https://evil.example',
        'Content-Type': 'application/json',
        Accept: 'application/json, text/event-stream',
      },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: MCP_INITIALIZE }),
    })
    expect(response.status).toBe(403)
  })

  it('stops accepting tokens after POST /api/oauth/revoke-all', async () => {
    const accessToken = await getAccessToken()
    expect((await mcpCall(accessToken, 'initialize', MCP_INITIALIZE)).status).toBe(200)
    const { token } = await loginDevice()
    const revoked = await api('/api/oauth/revoke-all', { token, body: {} })
    expect(revoked.body).toEqual({ ok: true, revoked: 1 })
    expect((await mcpCall(accessToken, 'initialize', MCP_INITIALIZE)).status).toBe(401)
  })
})
