import { describe, expect, it } from 'vitest'
import { clientKey } from '../src/auth/clientKey'
import { isAllowedConsentHost, isAllowedRegistrationRedirect } from '../src/auth/redirects'
import { isIsoDate, isValidTimeZone, localDate, localNoon } from '../src/lib/time'

describe('time', () => {
  it('validates calendar dates and time zones', () => {
    expect(isIsoDate('2026-09-30')).toBe(true)
    expect(isIsoDate('2026-02-29')).toBe(false)
    expect(isIsoDate('2024-02-29')).toBe(true)
    expect(isIsoDate('2026-9-30')).toBe(false)
    expect(isValidTimeZone('Europe/Madrid')).toBe(true)
    expect(isValidTimeZone('Mars/Olympus')).toBe(false)
  })

  it('computes local noon and local dates across DST changes', () => {
    expect(localNoon('2026-09-30', 'UTC')).toBe(Date.parse('2026-09-30T12:00:00Z'))
    expect(localNoon('2026-07-01', 'Europe/Madrid')).toBe(Date.parse('2026-07-01T10:00:00Z'))
    expect(localNoon('2026-01-15', 'Europe/Madrid')).toBe(Date.parse('2026-01-15T11:00:00Z'))
    expect(localNoon('2026-03-29', 'Europe/Madrid')).toBe(Date.parse('2026-03-29T10:00:00Z'))
    expect(localNoon('2026-09-30', 'Pacific/Kiritimati')).toBe(Date.parse('2026-09-29T22:00:00Z'))
    expect(localDate(Date.parse('2026-09-30T02:00:00Z'), 'America/Los_Angeles')).toBe('2026-09-29')
  })
})

describe('client key', () => {
  const key = (ip?: string) => clientKey(new Request('https://x.test', { headers: ip ? { 'CF-Connecting-IP': ip } : {} }))

  it('uses IPv4 addresses as they are and IPv6 /64 prefixes', () => {
    expect(key('203.0.113.7')).toBe('203.0.113.7')
    expect(key('2001:db8:1:2:3:4:5:6')).toBe('2001:db8:1:2::/64')
    expect(key('2001:DB8:1:2::9')).toBe('2001:db8:1:2::/64')
    expect(key('2001:db8::1')).toBe('2001:db8:0:0::/64')
    expect(key('::1')).toBe('0:0:0:0::/64')
    expect(key()).toBe('unknown')
  })
})

describe('redirect allowlists', () => {
  const extra = new Set(['partner.example.com'])

  it('accepts only Claude, loopback /callback and configured hosts at registration', () => {
    expect(isAllowedRegistrationRedirect('https://claude.ai/api/mcp/auth_callback', extra)).toBe(true)
    expect(isAllowedRegistrationRedirect('https://claude.com/api/mcp/auth_callback', extra)).toBe(true)
    expect(isAllowedRegistrationRedirect('http://localhost:6274/callback', extra)).toBe(true)
    expect(isAllowedRegistrationRedirect('http://127.0.0.1/callback', extra)).toBe(true)
    expect(isAllowedRegistrationRedirect('https://partner.example.com/cb', extra)).toBe(true)
    expect(isAllowedRegistrationRedirect('http://partner.example.com/cb', extra)).toBe(false)
    expect(isAllowedRegistrationRedirect('https://claude.ai/api/mcp/auth_callback?x=1', extra)).toBe(false)
    expect(isAllowedRegistrationRedirect('http://localhost:6274/callback/x', extra)).toBe(false)
    expect(isAllowedRegistrationRedirect('https://evil.example/callback', extra)).toBe(false)
    expect(isAllowedRegistrationRedirect('not a url', extra)).toBe(false)
  })

  it('accepts only Claude, loopback and configured hosts on the consent page', () => {
    for (const host of ['claude.ai', 'claude.com', 'localhost', '127.0.0.1', 'partner.example.com']) expect(isAllowedConsentHost(host, extra)).toBe(true)
    expect(isAllowedConsentHost('evil.example', extra)).toBe(false)
  })
})
