import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import { createProposal, getDoc, getDocs, getExWeights, getProposal, listBodyweight, listWorkouts } from '../src/db'
import { api, loginDevice, resetDatabase, sampleOpenGymState, sampleWorkout, seedBodyweight, seedDoc, seedWorkouts } from './helpers'

let token: string

beforeEach(async () => {
  await resetDatabase()
  token = (await loginDevice('Mac', { 'X-Timezone': 'America/Puerto_Rico' })).token
})

const importState = (state: unknown, mode?: string) => api('/api/import/opengym', { token, body: { state, ...(mode && { mode }) } })

describe('POST /api/import/opengym (replace)', () => {
  it('maps a realistic openGym backup onto docs and rows', async () => {
    const result = await importState(sampleOpenGymState())
    expect(result.status).toBe(200)
    expect(result.body).toEqual({ imported: { workouts: 2, bodyweight: 2, routines: 2 }, skipped: { workouts: 0, bodyweight: 0, exWeights: 0 } })

    const docs = await getDocs(env.DB)
    expect(docs.settings.data).toEqual({
      unit: 'kg', restSec: 90, sound: true, keepAwake: true, lang: 'es', theme: 'dark', accent: 'lime', body: 'male',
      gifSize: 'full', effort: 'rir', showRir: true, targetW: 77,
      reminder: { on: true, time: '07:30', tz: 'America/Puerto_Rico' },
      futureSetting: { kept: true },
    })
    expect(docs.plan.data.routines).toEqual(sampleOpenGymState().routines)
    expect(docs.plan.data.week).toEqual({ '1': 'muo979oo50vo1', '3': 'muo979oohb54d' })
    expect(docs.plan.data.customEx).toEqual([
      { id: 'cmuo9zz12abc', n: 'Nordic curl', bp: 'upper legs', desc: '', tg: '', eq: 'custom', custom: true },
      { id: 'kx2plan0cust', n: 'Sled sprint', bp: 'cardio', desc: 'Outdoor sled', tg: '', eq: 'custom', custom: true },
    ])
    expect(docs.schedule.data).toEqual({ dayPlan: { '2026-09-30': 'muo979oo50vo1', '2026-10-02': 'rest' } })
    expect(docs.coach.data).toEqual({
      log: [{ at: 1790500000000, kind: 'review', outcome: 'applied', accepted: 1, rejected: 0 }],
      snapshots: [],
      lastReview: { at: 1790500000000 },
    })
    expect(docs.athlete.data).toEqual({
      goal: 'strength', experience: 'regular', daysPerWeek: 3, preferredDays: [1, 3, 5], sessionMin: 60,
      equipment: ['barbell', 'dumbbell'], limitations: 'Left shoulder', likes: '', dislikes: '', notes: '',
      savedAt: expect.any(Number), updatedBy: 'import',
    })
    for (const key of ['settings', 'plan', 'schedule', 'coach', 'athlete'] as const) {
      expect(JSON.stringify(docs[key].data)).not.toMatch(/consent|cadence|_ts|"active"/)
    }

    const workouts = await listWorkouts(env.DB)
    expect(workouts.map(w => w.id)).toEqual(['iwmuo1imported', 'muo979osyicjp'])
    const [imported, push] = workouts
    // A missing start becomes local noon of `d` in the owner's zone (UTC-4 in Puerto Rico).
    expect(imported!.start).toBe(Date.parse('2026-09-21T16:00:00Z'))
    expect(imported!.data.start).toBe(imported!.start)
    expect(imported!.data.entries).toEqual([{ id: '0025', sets: [{ w: 72.5, r: 8, done: true }], topW: 72.5 }])
    const targets = (push!.data.entries as any[]).map(e => e.target)
    expect(targets).toEqual([
      { id: '0025', sets: 4, mode: 'reps', reps: 8, weight: 60 },
      { id: '0001', sets: 3, sec: 45, weight: 0, mode: 'reps' },
      { id: '0685', sets: 1, min: 20, speed: 8, mode: 'cardio' },
      { id: 'kx2plan0cust', sets: 3, reps: 10, mode: 'cardio' },
    ])
    expect(push!.data).toEqual(expect.objectContaining({ rating: 'right', note: 'Felt strong', prs: ['0025'] }))

    expect(await listBodyweight(env.DB)).toEqual([
      { d: '2026-09-21', w: 79.2, t: 1790000000000 },
      { d: '2026-09-28', w: 78.7, t: 1790580600000 },
    ])
    expect(await getExWeights(env.DB)).toEqual({ '0025': { w: 75, d: '2026-09-28' }, '0251': { w: 0, d: '2026-09-21' } })
  })

  it('tombstones rows missing from the file and supersedes pending proposals', async () => {
    await seedWorkouts([sampleWorkout('old-workout', '2026-01-05')])
    await seedBodyweight([{ d: '2026-01-05', w: 81 }])
    const pending = await createProposal(env.DB, { kind: 'plan', summary: 'x', body: { bundle: {} } })
    await importState(sampleOpenGymState())

    const row = await env.DB.prepare('SELECT deleted, data FROM workouts WHERE id = ?').bind('old-workout').first()
    expect(row).toEqual({ deleted: 1, data: null })
    expect((await listBodyweight(env.DB)).map(b => b.d)).toEqual(['2026-09-21', '2026-09-28'])
    expect((await getProposal(env.DB, pending.id))?.status).toBe('superseded')

    // The deletions reach other devices through a pull.
    const pulled = await api('/api/sync?since=0', { token })
    expect(pulled.body.workouts.find((w: any) => w.id === 'old-workout')).toEqual(expect.objectContaining({ deleted: true, data: null }))
  })

  it('keeps server rows a replace import skipped as malformed, and reports them', async () => {
    await seedWorkouts([sampleWorkout('w-keep', '2026-09-20')])
    const state = sampleOpenGymState() as any
    state.workouts = [...state.workouts, { ...(sampleWorkout('w-keep', '2026-09-20').data as object), id: 'w-keep', d: '2026-09-20T18:07:00' }]
    const result = await importState(state)
    expect(result.body.skipped).toEqual({ workouts: 1, bodyweight: 0, exWeights: 0 })
    const row = await env.DB.prepare('SELECT deleted FROM workouts WHERE id = ?').bind('w-keep').first<{ deleted: number }>()
    expect(row?.deleted).toBe(0)
  })

  it('is idempotent', async () => {
    await importState(sampleOpenGymState())
    const again = await importState(sampleOpenGymState())
    expect(again.status).toBe(200)
    expect((await listWorkouts(env.DB)).length).toBe(2)
    expect((await getDoc(env.DB, 'plan')).data.routines).toHaveLength(2)
  })

  it('wins over rows a device stamped with a newer clock', async () => {
    const future = Date.now() + 5 * 60_000
    await seedWorkouts([sampleWorkout('muo979osyicjp', '2026-09-28', { note: 'device copy' })], future)
    await importState(sampleOpenGymState())
    const row = await env.DB.prepare('SELECT data, updated_at FROM workouts WHERE id = ?').bind('muo979osyicjp').first<{ data: string; updated_at: number }>()
    expect(JSON.parse(row!.data).note).toBe('Felt strong')
    expect(row!.updated_at).toBeGreaterThan(future)
  })

  it('refuses files that are not openGym backups', async () => {
    for (const state of [null, [], { workouts: [] }, { routines: [], workouts: {} }]) {
      const result = await importState(state)
      expect(result.status).toBe(400)
      expect(result.body.error).toBe('No es una copia de openGym')
    }
    expect((await importState(sampleOpenGymState(), 'append')).status).toBe(400)
  })

  it('imports hundreds of workouts across several batches', async () => {
    const state = sampleOpenGymState()
    state.workouts = Array.from({ length: 450 }, (_, i) => {
      const d = new Date(Date.UTC(2024, 0, 1) + i * 86_400_000).toISOString().slice(0, 10)
      return sampleWorkout(`w${i}`, d)
    })
    const result = await importState(state)
    expect(result.body.imported.workouts).toBe(450)
    expect((await listWorkouts(env.DB)).length).toBe(450)
  })
})

describe('POST /api/import/opengym (merge)', () => {
  it('upserts the file without tombstoning or superseding', async () => {
    await seedWorkouts([sampleWorkout('kept-workout', '2026-01-05')])
    const pending = await createProposal(env.DB, { kind: 'plan', summary: 'x', body: { bundle: {} } })
    const result = await importState(sampleOpenGymState(), 'merge')
    expect(result.status).toBe(200)
    expect((await listWorkouts(env.DB)).map(w => w.id)).toEqual(['kept-workout', 'iwmuo1imported', 'muo979osyicjp'])
    expect((await getProposal(env.DB, pending.id))?.status).toBe('pending')
  })

  it('leaves the athlete doc alone when the file has no Coach profile', async () => {
    await seedDoc('athlete', { goal: 'muscle', savedAt: 1, updatedBy: 'app' })
    const state = sampleOpenGymState()
    state.coach = null
    await importState(state, 'merge')
    expect((await getDoc(env.DB, 'athlete')).data).toEqual({ goal: 'muscle', savedAt: 1, updatedBy: 'app' })
    expect((await getDoc(env.DB, 'coach')).data).toEqual({ log: [], snapshots: [], lastReview: null })
  })
})

describe('POST /api/reset', () => {
  it('tombstones every row, writes default docs and dismisses pending proposals', async () => {
    await importState(sampleOpenGymState())
    const pending = await createProposal(env.DB, { kind: 'changes', summary: 'x', body: { changes: [] } })
    expect((await api('/api/reset', { token, body: { confirm: 'reset' } })).status).toBe(400)

    const result = await api('/api/reset', { token, body: { confirm: 'RESET' } })
    expect(result.status).toBe(200)
    expect(result.body).toEqual({ ok: true, seq: expect.any(Number) })
    expect(await listWorkouts(env.DB)).toEqual([])
    expect(await listBodyweight(env.DB)).toEqual([])
    expect(await getExWeights(env.DB)).toEqual({})
    const docs = await getDocs(env.DB)
    expect(docs.athlete.data.savedAt).toBeNull()
    expect(docs.plan.data).toEqual({ routines: [], week: {}, customEx: [] })
    expect(docs.settings.data.lang).toBe('es')
    expect(docs.plan.seq).toBe(result.body.seq)
    expect(await getProposal(env.DB, pending.id)).toEqual(expect.objectContaining({ status: 'dismissed', seq: result.body.seq }))

    const pulled = await api('/api/sync?since=0', { token })
    expect(pulled.body.workouts.every((w: any) => w.deleted)).toBe(true)
  })
})
