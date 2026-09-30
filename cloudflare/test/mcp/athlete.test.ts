import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import { getCounters, getDoc } from '../../src/db'
import { api, seedDoc } from '../helpers'
import { fillLimit, freshOwner, McpClient } from './client'

let client: McpClient
let device: string

beforeEach(async () => {
  ;({ client, device } = await freshOwner())
})

describe('update_athlete_profile', () => {
  it('saves a first profile, normalised, stamped as written by Claude', async () => {
    const before = Date.now()
    const result = await client.ok('update_athlete_profile', {
      goal: 'strength',
      experience: 'returning',
      daysPerWeek: 4,
      preferredDays: [5, 1, 3, 1],
      equipment: ['Barra', 'mancuerna', 'cable', 'dumbbell'],
      limitations: '  Rodilla derecha operada hace un año  ',
    })
    expect(result.changed).toEqual(['goal', 'experience', 'daysPerWeek', 'preferredDays', 'equipment', 'limitations'])
    expect(result.athlete).toEqual({
      goal: 'strength', experience: 'returning', daysPerWeek: 4, preferredDays: [1, 3, 5], sessionMin: 45,
      equipment: ['barbell', 'dumbbell', 'cable'], limitations: 'Rodilla derecha operada hace un año', likes: '', dislikes: '', notes: '',
      savedAt: expect.stringMatching(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/), updatedBy: 'claude',
    })

    // What the app pulls.
    const sync = await api('/api/sync?since=0', { token: device })
    const athlete = sync.body.docs.find((doc: { key: string }) => doc.key === 'athlete')
    expect(athlete.data.updatedBy).toBe('claude')
    expect(athlete.data.savedAt).toBeGreaterThanOrEqual(before)
    expect(athlete.data.savedAt).toBeLessThanOrEqual(Date.now())
  })

  it('merges into the stored profile with compare-and-swap on its version', async () => {
    const seq = await seedDoc('athlete', {
      goal: 'muscle', experience: 'regular', daysPerWeek: 3, preferredDays: [1, 3, 5], sessionMin: 45, equipment: [],
      limitations: '', likes: 'dominadas', dislikes: '', notes: '', savedAt: 1790000000000, updatedBy: 'app', appOnly: { kept: true },
    })
    await client.ok('update_athlete_profile', { sessionMin: 60, goal: null })
    const stored = await getDoc(env.DB, 'athlete')
    expect(stored.seq).toBeGreaterThan(seq)
    expect(stored.data).toEqual(expect.objectContaining({ goal: null, sessionMin: 60, likes: 'dominadas', appOnly: { kept: true }, updatedBy: 'claude' }))

    // A device that edited the old version loses, as with any concurrent edit; from the new one it wins.
    const push = (baseSeq: number) =>
      api('/api/sync', { token: device, body: { since: 0, docs: [{ key: 'athlete', data: { ...stored.data, sessionMin: 30, updatedBy: 'app' }, baseSeq, updatedAt: Date.now() }] } })
    expect((await push(seq)).body.conflicts).toEqual([{ kind: 'doc', key: 'athlete' }])
    expect((await push(stored.seq)).body.conflicts).toEqual([])
  })

  it('reports every unknown equipment value and refuses an empty update', async () => {
    const unknown = await client.call('update_athlete_profile', { equipment: ['barbell', 'moon rocks', 'jetpack'] })
    expect(unknown.isError).toBe(true)
    expect(unknown.data.errors).toEqual(['equipment "moon rocks" is not a library equipment value', 'equipment "jetpack" is not a library equipment value'])
    expect((await client.call('update_athlete_profile', {})).isError).toBe(true)
    const outOfRange = await client.call('update_athlete_profile', { daysPerWeek: 9, sessionMin: 5 })
    expect(outOfRange.isError).toBe(true)
    expect(outOfRange.text).toContain('daysPerWeek')
    expect(outOfRange.text).toContain('sessionMin')
    expect((await getDoc(env.DB, 'athlete')).seq).toBe(0)
  })

  it('allows 10 updates per 24 hours', async () => {
    await fillLimit('athlete', 9)
    expect((await client.call('update_athlete_profile', { notes: 'Décima.' })).isError).toBe(false)
    const counters = await getCounters(env.DB)
    const limited = await client.call('update_athlete_profile', { notes: 'Undécima.' })
    expect(limited.isError).toBe(true)
    expect(limited.text).toContain('at most 10 profile updates per 24 hours')
    expect(await getCounters(env.DB)).toEqual(counters)
    expect((await getDoc(env.DB, 'athlete')).data.notes).toBe('Décima.')
  })
})
