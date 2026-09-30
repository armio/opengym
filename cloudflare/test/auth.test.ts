import { createExecutionContext, waitOnExecutionContext } from 'cloudflare:test'
import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from '../src/index'
import { APP_ORIGIN, ORIGIN, PASSWORD, api, fetchWorker, loginDevice, resetDatabase } from './helpers'

beforeEach(resetDatabase)

describe('GET /api/health', () => {
  it('answers without auth and leaks no counts', async () => {
    const { status, body, headers } = await api('/api/health')
    expect(status).toBe(200)
    expect(body).toEqual({ ok: true, version: expect.any(String) })
    expect(headers.get('Cache-Control')).toBe('no-store')
  })
})

describe('POST /api/auth/login', () => {
  it('issues a device token for the owner password and stores only its hash', async () => {
    const { status, body } = await api('/api/auth/login', {
      body: { password: PASSWORD, deviceName: '  Pixel 9  ' },
      headers: { 'X-Timezone': 'Europe/Madrid' },
    })
    expect(status).toBe(200)
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/)
    expect(body.deviceId).toMatch(/^d[0-9a-f]{16}$/)
    const row = await env.DB.prepare('SELECT name, token_hash, tz FROM devices WHERE id = ?').bind(body.deviceId).first<any>()
    expect(row.name).toBe('Pixel 9')
    expect(row.tz).toBe('Europe/Madrid')
    expect(row.token_hash).toMatch(/^[0-9a-f]{64}$/)
    expect(row.token_hash).not.toContain(body.token)
  })

  it('defaults and truncates the device name', async () => {
    const unnamed = await api('/api/auth/login', { body: { password: PASSWORD } })
    const long = await api('/api/auth/login', { body: { password: PASSWORD, deviceName: 'x'.repeat(80) } })
    const names = await env.DB.prepare('SELECT id, name FROM devices').all<{ id: string; name: string }>()
    const nameOf = (id: string) => names.results.find(row => row.id === id)?.name
    expect(nameOf(unnamed.body.deviceId)).toBe('Dispositivo')
    expect(nameOf(long.body.deviceId)).toHaveLength(60)
  })

  it('rejects a wrong password with 401 and a Spanish message', async () => {
    const { status, body } = await api('/api/auth/login', { body: { password: 'nope nope nope' } })
    expect(status).toBe(401)
    expect(body).toEqual({ error: 'Contraseña incorrecta.' })
  })

  it('rate-limits a client after 10 failures in 15 minutes, even for the right password', async () => {
    const headers = { 'CF-Connecting-IP': '203.0.113.7' }
    for (let i = 0; i < 10; i++) {
      expect((await api('/api/auth/login', { body: { password: 'wrong password!' }, headers })).status).toBe(401)
    }
    const limited = await api('/api/auth/login', { body: { password: PASSWORD }, headers })
    expect(limited.status).toBe(429)
    expect(limited.headers.get('Retry-After')).toBe('900')
    // Another client is unaffected.
    expect((await api('/api/auth/login', { body: { password: PASSWORD }, headers: { 'CF-Connecting-IP': '198.51.100.1' } })).status).toBe(200)
  })

  it('keys IPv6 clients by their /64', async () => {
    for (let i = 0; i < 10; i++) {
      await api('/api/auth/login', { body: { password: 'wrong password!' }, headers: { 'CF-Connecting-IP': `2001:db8:1:2::${i + 1}` } })
    }
    const sameSubnet = await api('/api/auth/login', { body: { password: PASSWORD }, headers: { 'CF-Connecting-IP': '2001:db8:1:2:ffff::9' } })
    expect(sameSubnet.status).toBe(429)
  })

  it('applies the global limit of 200 attempts per hour', async () => {
    const now = Date.now()
    await env.DB.batch(Array.from({ length: 200 }, (_, i) => env.DB.prepare('INSERT INTO auth_failures (ip, at) VALUES (?, ?)').bind(`10.0.${i >> 8}.${i & 255}`, now)))
    expect((await api('/api/auth/login', { body: { password: PASSWORD }, headers: { 'CF-Connecting-IP': '192.0.2.50' } })).status).toBe(429)
  })

  it('does not count successful logins', async () => {
    const headers = { 'CF-Connecting-IP': '203.0.113.9' }
    for (let i = 0; i < 12; i++) expect((await api('/api/auth/login', { body: { password: PASSWORD }, headers })).status).toBe(200)
  })

  it('fails with 500 when OWNER_PASSWORD is missing or shorter than 12 characters', async () => {
    for (const OWNER_PASSWORD of [undefined, 'short']) {
      const ctx = createExecutionContext()
      const request = new Request(`${ORIGIN}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: 'short' }),
      })
      const response = await worker.fetch(request as Request<unknown, IncomingRequestCfProperties>, { ...env, OWNER_PASSWORD }, ctx)
      await waitOnExecutionContext(ctx)
      expect(response.status).toBe(500)
      expect(await response.json()).toEqual({ error: 'Servidor mal configurado: define OWNER_PASSWORD (mínimo 12 caracteres)' })
    }
  })

  it('answers malformed bodies with 400', async () => {
    const response = await fetchWorker('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{nope' })
    expect(response.status).toBe(400)
    expect((await api('/api/auth/login', { body: { deviceName: 'x' } })).status).toBe(400)
  })
})

describe('request rules', () => {
  it('requires a device token on every other endpoint', async () => {
    for (const [method, path] of [
      ['GET', '/api/sync'],
      ['GET', '/api/devices'],
      ['POST', '/api/sync'],
      ['POST', '/api/reset'],
    ] as const) {
      const result = await api(path, { method, body: method === 'POST' ? {} : undefined })
      expect(result.status, path).toBe(401)
      expect(result.body.error).toMatch(/Inicia sesión/)
    }
    expect((await api('/api/sync', { token: 'not-a-real-token' })).status).toBe(401)
  })

  it('rejects POSTs that are not application/json with 415', async () => {
    const response = await fetchWorker('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: '{}' })
    expect(response.status).toBe(415)
    const { token } = await loginDevice()
    const noType = await fetchWorker('/api/sync', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: '{}' })
    expect(noType.status).toBe(415)
    const withCharset = await fetchWorker('/api/sync', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json; charset=utf-8' },
      body: '{}',
    })
    expect(withCharset.status).toBe(200)
  })

  it('answers unknown routes with 404 and wrong methods with 405', async () => {
    expect((await api('/api/nope')).status).toBe(404)
    const wrongMethod = await api('/api/health', { body: {} })
    expect(wrongMethod.status).toBe(405)
    expect(wrongMethod.headers.get('Allow')).toContain('GET')
  })
})

describe('CORS', () => {
  it('echoes only origins listed in APP_ORIGINS', async () => {
    const allowed = await api('/api/health', { headers: { Origin: APP_ORIGIN } })
    expect(allowed.headers.get('Access-Control-Allow-Origin')).toBe(APP_ORIGIN)
    const other = await api('/api/health', { headers: { Origin: 'https://evil.example' } })
    expect(other.status).toBe(200)
    expect(other.headers.get('Access-Control-Allow-Origin')).toBeNull()
  })

  it('answers preflights with the allowed headers and methods', async () => {
    const response = await fetchWorker('/api/sync', {
      method: 'OPTIONS',
      headers: { Origin: APP_ORIGIN, 'Access-Control-Request-Method': 'POST' },
    })
    expect(response.status).toBe(204)
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP_ORIGIN)
    expect(response.headers.get('Access-Control-Allow-Headers')).toBe('Authorization, Content-Type, X-Timezone')
    expect(response.headers.get('Access-Control-Allow-Methods')).toBe('GET, POST, OPTIONS')
    const denied = await fetchWorker('/api/sync', { method: 'OPTIONS', headers: { Origin: 'https://evil.example' } })
    expect(denied.headers.get('Access-Control-Allow-Origin')).toBeNull()
  })

  it('refuses /api/auth/* from an origin that is not allowed', async () => {
    const denied = await api('/api/auth/login', { body: { password: PASSWORD }, headers: { Origin: 'https://evil.example' } })
    expect(denied.status).toBe(403)
    const allowed = await api('/api/auth/login', { body: { password: PASSWORD }, headers: { Origin: APP_ORIGIN } })
    expect(allowed.status).toBe(200)
    expect(allowed.headers.get('Access-Control-Allow-Origin')).toBe(APP_ORIGIN)
  })
})

describe('devices', () => {
  it('lists devices, marks the caller and revokes another one', async () => {
    const phone = await loginDevice('Teléfono')
    const tablet = await loginDevice('Tableta')
    const list = await api('/api/devices', { token: phone.token })
    expect(list.status).toBe(200)
    expect(list.body).toEqual([
      expect.objectContaining({ id: phone.deviceId, name: 'Teléfono', current: true, createdAt: expect.any(Number) }),
      expect.objectContaining({ id: tablet.deviceId, name: 'Tableta', current: false }),
    ])
    expect((await api(`/api/devices/${tablet.deviceId}/revoke`, { token: phone.token, body: {} })).status).toBe(200)
    expect((await api('/api/sync', { token: tablet.token })).status).toBe(401)
    expect((await api(`/api/devices/${tablet.deviceId}/revoke`, { token: phone.token, body: {} })).status).toBe(404)
  })

  it('logs the calling device out', async () => {
    const { token } = await loginDevice()
    expect((await api('/api/auth/logout', { token, body: {} })).body).toEqual({ ok: true })
    expect((await api('/api/sync', { token })).status).toBe(401)
  })

  it('records the X-Timezone of the most recently seen device as the owner zone', async () => {
    const { ownerTimeZone } = await import('../src/db/devices')
    expect(await ownerTimeZone(env.DB)).toBe('UTC')
    const { token, deviceId } = await loginDevice('Mac')
    await api('/api/sync', { token, headers: { 'X-Timezone': 'America/Puerto_Rico' } })
    expect(await ownerTimeZone(env.DB)).toBe('America/Puerto_Rico')
    await api('/api/sync', { token, headers: { 'X-Timezone': 'Not/AZone' } })
    const row = await env.DB.prepare('SELECT tz FROM devices WHERE id = ?').bind(deviceId).first<{ tz: string }>()
    expect(row?.tz).toBe('America/Puerto_Rico')
  })
})
