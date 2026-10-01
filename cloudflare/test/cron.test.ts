import { createScheduledController } from 'cloudflare:test'
import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from '../src/index'
import { PURGE_CURSOR_KEY } from '../src/cron'
import { createProposal, getProposal } from '../src/db'
import { getAccessToken, resetDatabase } from './helpers'

beforeEach(resetDatabase)

async function runCron() {
  await worker.scheduled(createScheduledController({ cron: '17 4 * * *', scheduledTime: Date.now() }), env)
}

describe('daily cron', () => {
  it('prunes day-old auth failures and rate-limit rows, and expires overdue proposals', async () => {
    const now = Date.now()
    const old = now - 2 * 86_400_000
    await env.DB.batch([
      env.DB.prepare('INSERT INTO auth_failures (ip, at) VALUES (?, ?), (?, ?)').bind('a', old, 'b', now),
      env.DB.prepare('INSERT INTO limits_log (kind, at) VALUES (?, ?), (?, ?)').bind('propose', old, 'propose', now),
    ])
    const overdue = await createProposal(env.DB, { kind: 'plan', summary: 'x', body: { bundle: {} } }, now - 15 * 86_400_000)
    await runCron()
    expect(await env.DB.prepare('SELECT ip FROM auth_failures').all().then(r => r.results)).toEqual([{ ip: 'b' }])
    expect(await env.DB.prepare('SELECT count(*) AS n FROM limits_log').first('n')).toBe(1)
    expect((await getProposal(env.DB, overdue.id))?.status).toBe('expired')
  })

  it('sweeps OAuth KV data and leaves live grants alone', async () => {
    await getAccessToken()
    await runCron()
    expect(await env.OAUTH_KV.get(PURGE_CURSOR_KEY)).toBeNull()
    const grants = await env.OAUTH_KV.list({ prefix: 'grant:' })
    expect(grants.keys.length).toBe(1)
  })
})
