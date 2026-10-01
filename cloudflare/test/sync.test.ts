import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import { createProposal, getCounters } from '../src/db'
import { api, loginDevice, resetDatabase, sampleWorkout, seedDoc } from './helpers'

let token: string

beforeEach(async () => {
  await resetDatabase()
  token = (await loginDevice()).token
})

const push = (body: object) => api('/api/sync', { token, body: { since: 0, ...body } })
const pull = (since = 0) => api(`/api/sync?since=${since}`, { token })

const workoutItem = (id: string, updatedAt: number, overrides: object = {}) => {
  const data = sampleWorkout(id, '2026-09-28')
  return { id, d: data.d, start: data.start, routineId: data.routineId, updatedAt, deleted: false, data, ...overrides }
}

describe('GET /api/sync', () => {
  it('returns an empty first pull with the counters', async () => {
    const { status, body } = await pull()
    expect(status).toBe(200)
    expect(body).toEqual({
      seq: 0,
      epoch: expect.any(Number),
      serverTime: expect.any(Number),
      hasMore: false,
      docs: [],
      workouts: [],
      bodyweight: [],
      exWeights: [],
      proposals: [],
      conflicts: [],
      rejected: [],
    })
    const counters = await getCounters(env.DB)
    expect(body.epoch).toBe(counters.epoch)
    expect((await pull()).body.epoch).toBe(body.epoch)
  })

  it('never writes, not even to expire proposals', async () => {
    const proposal = await createProposal(env.DB, { kind: 'nochange', summary: 'Todo bien', body: { reading: 'Sigue así.' } }, Date.now() - 20 * 86_400_000)
    const before = await getCounters(env.DB)
    const { body } = await pull()
    expect(body.proposals).toEqual([expect.objectContaining({ id: proposal.id, status: 'pending' })])
    expect(await getCounters(env.DB)).toEqual(before)
    const row = await env.DB.prepare('SELECT status, seq FROM proposals WHERE id = ?').bind(proposal.id).first()
    expect(row).toEqual({ status: 'pending', seq: proposal.seq })
  })

  it('rejects a malformed since', async () => {
    expect((await api('/api/sync?since=-1', { token })).status).toBe(400)
    expect((await api('/api/sync?since=abc', { token })).status).toBe(400)
  })
})

describe('docs: compare-and-swap', () => {
  it('creates a doc from baseSeq 0 and updates it from the returned seq', async () => {
    const now = Date.now()
    const first = await push({ docs: [{ key: 'plan', data: { routines: [], week: {}, customEx: [] }, baseSeq: 0, updatedAt: now }] })
    expect(first.status).toBe(200)
    expect(first.body.conflicts).toEqual([])
    expect(first.body.docs).toEqual([{ key: 'plan', data: { routines: [], week: {}, customEx: [] }, updatedAt: now, seq: first.body.seq }])

    const second = await push({
      since: first.body.seq,
      docs: [{ key: 'plan', data: { routines: [{ id: 'r1', name: 'Empuje', emoji: 'barbell', ex: [] }], week: {}, customEx: [] }, baseSeq: first.body.seq, updatedAt: now + 1 }],
    })
    expect(second.body.conflicts).toEqual([])
    expect(second.body.docs[0].seq).toBe(second.body.seq)
    expect(second.body.docs[0].data.routines).toHaveLength(1)
  })

  it('reports a stale baseSeq as a conflict and returns the server version', async () => {
    const seq = await seedDoc('settings', { unit: 'lb' })
    const result = await push({ since: seq, docs: [{ key: 'settings', data: { unit: 'kg' }, baseSeq: seq - 1, updatedAt: Date.now() }] })
    expect(result.body.conflicts).toEqual([{ kind: 'doc', key: 'settings' }])
    expect(result.body.docs).toEqual([expect.objectContaining({ key: 'settings', data: { unit: 'lb' }, seq })])

    const fresh = await push({ docs: [{ key: 'settings', data: { unit: 'kg' }, baseSeq: 0, updatedAt: Date.now() }] })
    expect(fresh.body.conflicts).toEqual([{ kind: 'doc', key: 'settings' }])
  })

  it('does not create a missing doc from a non-zero baseSeq', async () => {
    const result = await push({ docs: [{ key: 'coach', data: { log: [] }, baseSeq: 7, updatedAt: Date.now() }] })
    expect(result.body.conflicts).toEqual([{ kind: 'doc', key: 'coach' }])
    expect(await env.DB.prepare("SELECT count(*) AS n FROM docs WHERE key = 'coach'").first('n')).toBe(0)
  })
})

describe('rows: last writer wins', () => {
  it('keeps the newer row, echoes it to an older push, and keeps the stored row on a tie', async () => {
    const t = Date.now() - 60_000
    await push({ workouts: [workoutItem('w1', t, { data: { ...sampleWorkout('w1', '2026-09-28'), note: 'first' } })] })

    const older = await push({ workouts: [workoutItem('w1', t - 1000, { data: { ...sampleWorkout('w1', '2026-09-28'), note: 'older' } })] })
    expect(older.body.workouts).toEqual([expect.objectContaining({ id: 'w1', updatedAt: t, data: expect.objectContaining({ note: 'first' }) })])

    const tie = await push({ workouts: [workoutItem('w1', t, { data: { ...sampleWorkout('w1', '2026-09-28'), note: 'tie' } })] })
    expect(tie.body.workouts[0].data.note).toBe('first')

    const newer = await push({ workouts: [workoutItem('w1', t + 1000, { data: { ...sampleWorkout('w1', '2026-09-28'), note: 'newer' } })] })
    expect(newer.body.workouts[0]).toEqual(expect.objectContaining({ updatedAt: t + 1000, seq: newer.body.seq }))
    expect(newer.body.workouts[0].data.note).toBe('newer')
  })

  it('echoes the current version of pushed items even when their seq is at or below since', async () => {
    const t = Date.now() - 60_000
    const first = await push({ bodyweight: [{ d: '2026-09-28', w: 78.7, t, updatedAt: t }] })
    const stale = await push({ since: first.body.seq + 100, bodyweight: [{ d: '2026-09-28', w: 80, t, updatedAt: t - 1 }] })
    expect(stale.body.bodyweight).toEqual([{ d: '2026-09-28', w: 78.7, t, deleted: false, updatedAt: t, seq: first.body.seq }])
  })

  it('applies body weight and working weights, including a 0 working weight', async () => {
    const t = Date.now()
    const result = await push({
      bodyweight: [{ d: '2026-09-30', w: 78.7, t, updatedAt: t, deleted: false }],
      exWeights: [
        { id: '0025', w: 75, d: '2026-09-28', updatedAt: t, deleted: false },
        { id: '0251', w: 0, d: '2026-09-28', updatedAt: t },
      ],
    })
    expect(result.body.rejected).toEqual([])
    expect(result.body.bodyweight).toEqual([{ d: '2026-09-30', w: 78.7, t, deleted: false, updatedAt: t, seq: result.body.seq }])
    expect(result.body.exWeights).toEqual(
      expect.arrayContaining([
        { id: '0025', w: 75, d: '2026-09-28', deleted: false, updatedAt: t, seq: result.body.seq },
        { id: '0251', w: 0, d: '2026-09-28', deleted: false, updatedAt: t, seq: result.body.seq },
      ]),
    )
  })
})

describe('tombstones', () => {
  it('deletes rows with newer tombstones and stores tombstones for items the server never saw', async () => {
    const t = Date.now() - 60_000
    await push({
      workouts: [workoutItem('w1', t)],
      bodyweight: [{ d: '2026-09-28', w: 78.7, t, updatedAt: t }],
      exWeights: [{ id: '0025', w: 75, d: '2026-09-28', updatedAt: t }],
    })
    const deleted = await push({
      workouts: [
        { id: 'w1', d: '2026-09-28', start: 1, routineId: 'r-push', deleted: true, updatedAt: t + 1 },
        // Created and deleted while offline: the server only ever sees the tombstone.
        { id: 'offline1', d: '2026-09-29', start: null, routineId: null, deleted: true, updatedAt: t + 1 },
      ],
      bodyweight: [{ d: '2026-09-28', deleted: true, updatedAt: t + 1 }],
      exWeights: [{ id: '0025', deleted: true, updatedAt: t + 1 }],
    })
    expect(deleted.body.rejected).toEqual([])
    const byId = Object.fromEntries(deleted.body.workouts.map((w: any) => [w.id, w]))
    expect(byId.w1).toEqual(expect.objectContaining({ deleted: true, data: null, updatedAt: t + 1 }))
    expect(byId.offline1).toEqual(expect.objectContaining({ deleted: true, data: null, d: '2026-09-29' }))
    expect(deleted.body.bodyweight).toEqual([expect.objectContaining({ d: '2026-09-28', w: null, t: null, deleted: true })])
    expect(deleted.body.exWeights).toEqual([expect.objectContaining({ id: '0025', w: null, d: null, deleted: true })])

    // An older write cannot resurrect a tombstone.
    const resurrect = await push({ workouts: [workoutItem('w1', t)] })
    expect(resurrect.body.workouts.find((w: any) => w.id === 'w1')).toEqual(expect.objectContaining({ deleted: true }))
    // A newer one can (the same item re-created).
    const recreated = await push({ workouts: [workoutItem('w1', t + 2)] })
    expect(recreated.body.workouts.find((w: any) => w.id === 'w1')).toEqual(expect.objectContaining({ deleted: false, updatedAt: t + 2 }))
  })
})

describe('validation', () => {
  it('rejects invalid items one by one and applies the rest', async () => {
    const now = Date.now()
    const result = await push({
      docs: [
        { key: 'plan', data: { routines: [] }, baseSeq: 0, updatedAt: now },
        { key: 'secrets', data: {}, baseSeq: 0, updatedAt: now },
        { key: 'schedule', data: [], baseSeq: 0, updatedAt: now },
      ],
      workouts: [
        workoutItem('good', now),
        workoutItem('bad id!', now),
        workoutItem('future', now + 3_600_000),
        { ...workoutItem('baddate', now), d: '2026-02-30' },
        { id: 'nodata', d: '2026-09-28', updatedAt: now },
        workoutItem('good', now),
      ],
      bodyweight: [{ d: '2026-09-28', w: 0, updatedAt: now }, { d: '2026-09-29', w: 80, updatedAt: now }],
      exWeights: [{ id: '0025', w: -1, d: '2026-09-28', updatedAt: now }],
    })
    expect(result.status).toBe(200)
    expect(result.body.rejected).toEqual([
      { kind: 'doc', key: 'secrets', error: expect.any(String) },
      { kind: 'doc', key: 'schedule', error: expect.any(String) },
      { kind: 'workout', key: 'bad id!', error: expect.any(String) },
      { kind: 'workout', key: 'future', error: 'updatedAt no válido' },
      { kind: 'workout', key: 'baddate', error: 'fecha no válida' },
      { kind: 'workout', key: 'nodata', error: expect.any(String) },
      { kind: 'workout', key: 'good', error: 'repetido en la misma petición' },
      { kind: 'bodyweight', key: '2026-09-28', error: 'peso no válido' },
      { kind: 'exWeight', key: '0025', error: 'peso no válido' },
    ])
    expect(result.body.docs.map((d: any) => d.key)).toEqual(['plan'])
    expect(result.body.workouts.map((w: any) => w.id)).toEqual(['good'])
    expect(result.body.bodyweight.map((b: any) => b.d)).toEqual(['2026-09-29'])
  })

  it('answers a malformed envelope with 400', async () => {
    expect((await push({ docs: 'plan' })).status).toBe(400)
    expect((await push({ since: -3 })).status).toBe(400)
    expect((await api('/api/sync', { token, body: [] })).status).toBe(400)
    const tooMany = Array.from({ length: 101 }, (_, i) => workoutItem(`w${i}`, Date.now()))
    expect((await push({ workouts: tooMany })).status).toBe(400)
  })

  it('refuses bodies over 1 MiB', async () => {
    const big = { routines: [{ id: 'r', name: 'x'.repeat(1_100_000), ex: [] }] }
    const result = await push({ docs: [{ key: 'plan', data: big, baseSeq: 0, updatedAt: Date.now() }] })
    expect(result.status).toBe(413)
  })
})

describe('paging', () => {
  /** Inserts `count` body-weight rows with consecutive seqs starting at `firstSeq`. */
  async function seedSequentialRows(count: number, firstSeq: number, sameSeq = false) {
    await env.DB.prepare(
      `WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < ?1)
       INSERT INTO bodyweight (d, w, t, deleted, updated_at, seq)
       SELECT date('2020-01-01', '+' || i || ' days'), 80, NULL, 0, 1, CASE WHEN ?3 THEN ?2 ELSE ?2 + i END FROM n`,
    )
      .bind(count, firstSeq, sameSeq ? 1 : 0)
      .run()
    const last = sameSeq ? firstSeq : firstSeq + count - 1
    await env.DB.prepare("UPDATE counters SET value = ? WHERE name = 'seq'").bind(last).run()
  }

  it('returns at most 500 rows per page with hasMore and the last included seq', async () => {
    await seedSequentialRows(1200, 1)
    const first = await pull(0)
    expect(first.body.bodyweight).toHaveLength(500)
    expect(first.body.hasMore).toBe(true)
    expect(first.body.seq).toBe(500)
    const second = await pull(first.body.seq)
    expect(second.body.bodyweight).toHaveLength(500)
    expect(second.body.bodyweight[0].seq).toBe(501)
    expect(second.body.seq).toBe(1000)
    const third = await pull(second.body.seq)
    expect(third.body.bodyweight).toHaveLength(200)
    expect(third.body.hasMore).toBe(false)
    expect(third.body.seq).toBe(1200)
  })

  it('never splits the rows of one seq across pages', async () => {
    await seedSequentialRows(300, 1)
    await env.DB.prepare(
      `WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < 400)
       INSERT INTO ex_weights (ex_id, w, d, deleted, updated_at, seq) SELECT 'x' || i, 10, '2026-01-01', 0, 1, 301 FROM n`,
    ).run()
    await env.DB.prepare("UPDATE counters SET value = 301 WHERE name = 'seq'").run()
    const first = await pull(0)
    expect(first.body.bodyweight).toHaveLength(300)
    expect(first.body.exWeights).toHaveLength(0)
    expect(first.body).toEqual(expect.objectContaining({ hasMore: true, seq: 300 }))
    const second = await pull(300)
    expect(second.body.exWeights).toHaveLength(400)
    expect(second.body).toEqual(expect.objectContaining({ hasMore: false, seq: 301 }))
  })

  it('returns a single group larger than the page whole', async () => {
    await seedSequentialRows(700, 5, true)
    const page = await pull(0)
    expect(page.body.bodyweight).toHaveLength(700)
    expect(page.body).toEqual(expect.objectContaining({ hasMore: false, seq: 5 }))
  })
})

describe('proposal expiry on push', () => {
  it('flips overdue pending proposals to expired with a new seq, even on an empty push', async () => {
    // Created in this order so that the second creation does not already expire the first.
    await createProposal(env.DB, { kind: 'nochange', summary: 'Nota', body: { reading: 'ok' } })
    const old = await createProposal(env.DB, { kind: 'plan', summary: 'Plan', body: { bundle: {} } }, Date.now() - 15 * 86_400_000)
    const result = await push({ since: old.seq })
    expect(result.body.seq).toBe(old.seq + 1)
    expect(result.body.proposals).toEqual([expect.objectContaining({ id: old.id, status: 'expired', seq: old.seq + 1 })])
    const again = await push({ since: result.body.seq })
    expect(again.body.seq).toBe(result.body.seq)
  })
})
