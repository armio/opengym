import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import {
  casWriteDoc,
  defaultDocData,
  getCounters,
  getDoc,
  getDocs,
  getExWeights,
  getWorkout,
  listBodyweight,
  listWorkouts,
  type RateLimit,
} from '../src/db'
import { resetDatabase, sampleWorkout, seedBodyweight, seedDoc, seedWorkouts } from './helpers'

beforeEach(resetDatabase)

describe('docs', () => {
  it('fills never-written docs with their defaults at seq 0', async () => {
    const seq = await seedDoc('settings', { unit: 'lb' })
    const docs = await getDocs(env.DB)
    expect(docs.settings).toEqual({ key: 'settings', data: { unit: 'lb' }, updatedAt: expect.any(Number), seq })
    expect(docs.athlete).toEqual({ key: 'athlete', data: defaultDocData('athlete'), updatedAt: 0, seq: 0 })
    expect((await getDoc(env.DB, 'schedule')).data).toEqual({ dayPlan: {} })
  })
})

describe('casWriteDoc', () => {
  const limit: RateLimit = { kind: 'athlete', max: 2, windowMs: 86_400_000 }

  it('writes from the current seq, reports conflicts with the current doc, and counts only applied writes', async () => {
    const now = Date.now()
    const first = await casWriteDoc(env.DB, { key: 'athlete', data: { goal: 'strength' }, baseSeq: 0, updatedAt: now }, { now, limit })
    expect(first).toEqual({ status: 'written', doc: expect.objectContaining({ data: { goal: 'strength' }, seq: (await getCounters(env.DB)).seq }) })

    const stale = await casWriteDoc(env.DB, { key: 'athlete', data: { goal: 'muscle' }, baseSeq: 0, updatedAt: now }, { now, limit })
    expect(stale).toEqual({ status: 'conflict', doc: expect.objectContaining({ data: { goal: 'strength' } }) })

    const second = await casWriteDoc(env.DB, { key: 'athlete', data: { goal: 'muscle' }, baseSeq: (first as any).doc.seq, updatedAt: now }, { now, limit })
    expect(second.status).toBe('written')
    const third = await casWriteDoc(env.DB, { key: 'athlete', data: { goal: 'general' }, baseSeq: (second as any).doc.seq, updatedAt: now }, { now, limit })
    expect(third).toEqual({ status: 'rate-limited' })
    expect((await getDoc(env.DB, 'athlete')).data).toEqual({ goal: 'muscle' })
  })
})

describe('workouts', () => {
  it('lists live workouts by (d, start) with date bounds, limit and newest-first order', async () => {
    await seedWorkouts([
      sampleWorkout('late', '2026-09-28', { start: Date.parse('2026-09-28T19:00:00Z') }),
      sampleWorkout('early', '2026-09-28', { start: Date.parse('2026-09-28T07:00:00Z') }),
      sampleWorkout('before', '2026-09-20'),
      sampleWorkout('after', '2026-10-01'),
    ])
    await env.DB.prepare("UPDATE workouts SET deleted = 1, data = NULL WHERE id = 'after'").run()
    expect((await listWorkouts(env.DB)).map(w => w.id)).toEqual(['before', 'early', 'late'])
    expect((await listWorkouts(env.DB, { from: '2026-09-21', to: '2026-09-30' })).map(w => w.id)).toEqual(['early', 'late'])
    expect((await listWorkouts(env.DB, { order: 'desc', limit: 2 })).map(w => w.id)).toEqual(['late', 'early'])
    expect((await getWorkout(env.DB, 'late'))?.data.id).toBe('late')
    expect(await getWorkout(env.DB, 'after')).toBeNull()
  })
})

describe('body weight and working weights', () => {
  it('lists entries in date order within bounds', async () => {
    await seedBodyweight([{ d: '2026-09-28', w: 78.7 }, { d: '2026-09-21', w: 79.2, t: 5 }])
    expect(await listBodyweight(env.DB)).toEqual([{ d: '2026-09-21', w: 79.2, t: 5 }, { d: '2026-09-28', w: 78.7, t: null }])
    expect(await listBodyweight(env.DB, { from: '2026-09-22' })).toEqual([{ d: '2026-09-28', w: 78.7, t: null }])
  })

  it('maps live working weights by exercise id', async () => {
    await env.DB.prepare("INSERT INTO ex_weights (ex_id, w, d, deleted, updated_at, seq) VALUES ('0025', 75, '2026-09-28', 0, 1, 1), ('0031', NULL, NULL, 1, 1, 1)").run()
    expect(await getExWeights(env.DB)).toEqual({ '0025': { w: 75, d: '2026-09-28' } })
  })
})
