import { env } from 'cloudflare:workers'
import { beforeEach, describe, expect, it } from 'vitest'
import { Catalog } from '../../src/catalog/library'
import { planHash } from '../../src/coach'
import { getProposal, listProposals } from '../../src/db'
import { api, seedDoc, seedWorkouts } from '../helpers'
import { daysFrom, fillLimit, freshOwner, McpClient, repsEntry, workout } from './client'

let client: McpClient
let device: string
let today: string

beforeEach(async () => {
  ;({ client, device, today } = await freshOwner())
})

const BUNDLE = {
  name: 'Fuerza tres días',
  summary: 'Tres días de cuerpo completo con básicos.',
  basedOn: 'sin historial todavía',
  week: { '1': 'a', '3': 'b', '5': 'a' },
  routines: [
    {
      id: 'a', name: 'Día A', emoji: '🏋️', prog: 'linear', why: 'Básicos pesados.',
      ex: [
        { id: '0043', sets: 3, reps: 5, why: 'Sentadilla como base.' },
        { id: '0025', sets: 3, reps: 5, weight: 100 },
        // No mode: cardio for a cardio exercise.
        { id: '0685', sets: 1, min: 15, speed: 8 },
      ],
    },
    { id: 'b', name: 'Día B', emoji: '🦵', ex: [{ id: '0032', sets: 1, reps: 5 }, { id: '0334', sets: 3, reps: 12, prog: 'double', repsMin: 10, weight: 8 }] },
  ],
}

const CURRENT_PLAN = {
  routines: [{ id: 'r1', name: 'Torso', emoji: '💪', ex: [{ id: '0025', sets: 3, mode: 'reps', reps: 8 }, { id: '0334', sets: 3, mode: 'reps', reps: 12 }] }],
  week: { '1': 'r1' },
  customEx: [],
}

const change = (over: object = {}) => ({ id: 'c1', type: 'sets', target: { routineId: 'r1', exId: '0025' }, after: 4, why: 'Dos sesiones sin fallar a RIR 3.', ...over })

describe('propose_plan', () => {
  it('stores a valid plan the app then pulls, capping weights at what they have lifted', async () => {
    await seedWorkouts([workout('w1', daysFrom(today, -3), [repsEntry('0025', 60, [5, 5, 5])])])
    const result = await client.ok('propose_plan', BUNDLE)
    expect(result).toEqual({
      proposalId: expect.stringMatching(/^p[0-9a-f]{16}$/),
      status: 'pending',
      iteration: 1,
      unit: 'kg',
      summary: BUNDLE.summary,
      routines: [
        { id: 'a', name: 'Día A', exercises: 3, weekdays: ['monday', 'friday'] },
        { id: 'b', name: 'Día B', exercises: 2, weekdays: ['wednesday'] },
      ],
      warnings: [],
      message: expect.stringContaining('Coach tab'),
    })

    const sync = await api(`/api/sync?since=0`, { token: device })
    const stored = sync.body.proposals.find((p: { id: string }) => p.id === result.proposalId)
    expect(stored).toEqual(expect.objectContaining({ kind: 'plan', status: 'pending', unit: 'kg', iteration: 1, planHash: '76c7079ae0cff7e9', summary: BUNDLE.summary }))
    const [dayA, dayB] = stored.bundle.routines
    expect(dayA.ex[1]).toEqual({ id: '0025', sets: 3, mode: 'reps', reps: 5, weight: 60 })
    expect(dayA.ex[2]).toEqual({ id: '0685', sets: 1, mode: 'cardio', min: 15, speed: 8 })
    // Never trained: the starting weight stands.
    expect(dayB.ex[1]).toEqual({ id: '0334', sets: 3, mode: 'reps', reps: 12, weight: 8, prog: 'double', repsMin: 10 })
    expect(stored.bundle.week).toEqual({ '1': 'a', '3': 'b', '5': 'a' })
  })

  it('reports every validation problem at once and stores nothing', async () => {
    const result = await client.call('propose_plan', {
      summary: 'Plan roto',
      week: { '1': 'a', '2': 'ghost' },
      routines: [{ id: 'a', name: 'A', prog: 'time', ex: [{ id: 'not-a-real-id', sets: 3 }, { id: '0025', sets: 3, mode: 'cardio' }, { id: '0043', sets: 3, prog: 'time' }, { id: '0685', sets: 1, mode: 'reps' }] }],
    })
    expect(result.isError).toBe(true)
    // The routine prog is caught by the schema first, with its own message.
    expect(result.text).toContain('Input validation error')

    const semantic = await client.call('propose_plan', {
      name: 'Roto',
      summary: 'Plan roto',
      week: { '1': 'a', '2': 'ghost' },
      routines: [{ id: 'a', name: 'A', ex: [{ id: 'not-a-real-id', sets: 3 }, { id: '0025', sets: 3, mode: 'cardio' }, { id: '0043', sets: 3, prog: 'time' }, { id: '0685', sets: 1, mode: 'reps' }] }],
    })
    expect(semantic.isError).toBe(true)
    expect(semantic.data.error).toContain('not stored')
    expect(semantic.data.errors).toEqual(expect.arrayContaining([
      expect.stringContaining('routines[0].ex[0].id "not-a-real-id" is not in the exercise library'),
      'routines[0].ex[1].mode "cardio" is only for cardio exercises',
      'routines[0].ex[2].prog "time" is not allowed for mode "reps"',
      'routines[0].ex[3] is a cardio exercise and must use mode "cardio"',
      'week[2] points at "ghost", which is not one of the routines in this plan',
    ]))
    for (const error of semantic.data.errors) expect(semantic.text).toContain(`- ${error}`)
    expect(await listProposals(env.DB)).toEqual([])
  })

  it('enforces the training days of a saved profile and warns about equipment they lack', async () => {
    await seedDoc('athlete', { daysPerWeek: 2, preferredDays: [1, 4], equipment: ['dumbbell'], savedAt: 1790000000000, updatedBy: 'app' })
    const tooMany = await client.call('propose_plan', BUNDLE)
    expect(tooMany.data.errors).toEqual(['the week schedules 3 days but 2 were asked for'])
    const empty = await client.call('propose_plan', { ...BUNDLE, week: {} })
    expect(empty.data.errors).toEqual(['the plan needs at least one training day in "week"'])

    const result = await client.ok('propose_plan', { ...BUNDLE, week: { '1': 'a', '4': 'b' } })
    expect(result.warnings).toEqual(expect.arrayContaining([expect.stringContaining('"barbell bench press" (0025) needs barbell')]))
    expect(result.warnings.join(' ')).not.toContain('0334')
  })

  it('accepts the owner\'s custom exercises and new ones defined in the plan', async () => {
    await seedDoc('plan', { routines: [], week: {}, customEx: [{ id: 'cx-nordic', n: 'Nordic curl', bp: 'upper legs', desc: '', tg: '', eq: 'custom', custom: true }] })
    const result = await client.ok('propose_plan', {
      name: 'Isquios', summary: 'Isquios.', week: { '2': 'a' },
      routines: [{ id: 'a', name: 'Isquios', ex: [{ id: 'cx-nordic', sets: 3, reps: 6 }, { id: 'cx1', sets: 3, reps: 10 }] }],
      customEx: [{ id: 'cx1', n: 'Sandbag carry', bp: 'back', desc: 'Camina con el saco.' }],
    })
    const stored = await getProposal(env.DB, result.proposalId)
    expect((stored!.bundle as any).customEx).toEqual([{ id: 'cx1', n: 'Sandbag carry', bp: 'back', desc: 'Camina con el saco.' }])
  })

  it('refines an earlier plan proposal: iteration + 1, and the new one replaces it', async () => {
    const first = await client.ok('propose_plan', BUNDLE)
    const second = await client.ok('propose_plan', { ...BUNDLE, summary: 'Cambio: menos series de peso muerto.', refines: first.proposalId })
    expect(second.iteration).toBe(2)
    expect((await getProposal(env.DB, first.proposalId))?.status).toBe('superseded')
    expect((await getProposal(env.DB, second.proposalId))?.iteration).toBe(2)

    const unknown = await client.call('propose_plan', { ...BUNDLE, refines: 'p0000000000000000' })
    expect(unknown.data.errors).toEqual([expect.stringContaining('refines "p0000000000000000" is not a plan proposal')])
  })

  it('stores the owner\'s unit and the fingerprint of the plan it was made against', async () => {
    await seedDoc('settings', { unit: 'lb' })
    await seedDoc('plan', CURRENT_PLAN)
    const result = await client.ok('propose_plan', BUNDLE)
    const stored = await getProposal(env.DB, result.proposalId)
    expect(stored).toEqual(expect.objectContaining({ unit: 'lb', planHash: planHash(CURRENT_PLAN, Catalog.forPlan(CURRENT_PLAN)) }))
  })
})

describe('propose_changes', () => {
  beforeEach(async () => {
    await seedDoc('plan', CURRENT_PLAN)
  })

  it('records the actual current value as before and says where Claude read it wrong', async () => {
    const result = await client.ok('propose_changes', {
      summary: 'Más volumen en press.',
      evidence: { from: daysFrom(today, -14), to: today, sessions: 4 },
      changes: [change({ before: 5 }), change({ id: 'c2', type: 'reps', target: { routineId: 'r1', exId: '0334' }, after: 15 })],
      notes: ['Duerme más.'],
    })
    expect(result.changes).toEqual([
      { id: 'c1', type: 'sets', target: { routineId: 'r1', exId: '0025' }, before: 3, after: 4 },
      { id: 'c2', type: 'reps', target: { routineId: 'r1', exId: '0334' }, before: 12, after: 15 },
    ])
    expect(result.corrections).toEqual([{ id: 'c1', sent: 5, actual: 3 }])
    const stored = await getProposal(env.DB, result.proposalId)
    expect(stored).toEqual(expect.objectContaining({
      kind: 'changes', status: 'pending', unit: 'kg', planHash: planHash(CURRENT_PLAN, Catalog.forPlan(CURRENT_PLAN)),
      evidence: { from: daysFrom(today, -14), to: today, sessions: 4 }, notes: ['Duerme más.'],
    }))
    expect((stored!.changes as any[])[0]).toEqual(expect.objectContaining({ before: 3, why: 'Dos sesiones sin fallar a RIR 3.' }))
  })

  it('lists every problem against the current plan, one per change', async () => {
    const result = await client.call('propose_changes', {
      summary: 'Cambios rotos.',
      changes: [
        change({ target: { routineId: 'ghost', exId: '0025' } }),
        change({ id: 'c2', target: { routineId: 'r1', exId: '9999' } }),
        change({ id: 'c3', after: 99 }),
        change({ id: 'c4', type: 'reps', after: 10 }),
        change({ id: 'c4', type: 'repsMin', after: 6 }),
        change({ id: 'c6', type: 'reorder', target: { routineId: 'r1' }, after: ['0025', '0025'] }),
        change({ id: 'c7', type: 'add-exercise', target: { routineId: 'r1' }, after: { id: '0025', sets: 3, reps: 8 } }),
        change({ id: 'c8', type: 'superset', after: { link: true, with: '0025' } }),
      ],
    })
    expect(result.isError).toBe(true)
    expect(result.data.errors).toEqual([
      'changes[0].target.routineId "ghost" is not one of the routines in the plan',
      'changes[1].target.exId "9999" is not in routine "Torso"',
      'changes[2].after must be a whole number of sets (1-10)',
      'changes[4].id "c4" is already used by changes[3]',
      'changes[5].after must list exactly the 2 exercise ids already in "Torso", reordered',
      'changes[6].after.id "0025" is already in routine "Torso"',
      'changes[7].after.with must be a different exercise than target.exId',
    ])
    expect(await listProposals(env.DB)).toEqual([])
  })

  it('points at report_no_change when nothing is proposed', async () => {
    const result = await client.call('propose_changes', { summary: 'Nada.', changes: [] })
    expect(result.isError).toBe(true)
  })
})

describe('proposal lifecycle', () => {
  beforeEach(async () => {
    await seedDoc('plan', CURRENT_PLAN)
  })

  it('supersedes pending proposals of the same kind only; a no-change reading supersedes nothing', async () => {
    const plan = await client.ok('propose_plan', BUNDLE)
    const changes1 = await client.ok('propose_changes', { summary: 'Uno.', changes: [change()] })
    const reading = await client.ok('report_no_change', { reading: 'El bloque fue bien: progresas en press y no faltaste ningún día.' })
    expect(reading).toEqual({ proposalId: expect.any(String), status: 'pending', reading: 'El bloque fue bien: progresas en press y no faltaste ningún día.', message: expect.any(String) })
    const changes2 = await client.ok('propose_changes', { summary: 'Dos.', changes: [change({ after: 5 })] })

    const status = async (id: string) => (await getProposal(env.DB, id))?.status
    expect(await status(plan.proposalId)).toBe('pending')
    expect(await status(changes1.proposalId)).toBe('superseded')
    expect(await status(reading.proposalId)).toBe('pending')
    expect(await status(changes2.proposalId)).toBe('pending')

    const stored = await getProposal(env.DB, reading.proposalId)
    expect(stored).toEqual(expect.objectContaining({ kind: 'nochange', reading: expect.stringContaining('El bloque fue bien'), planHash: expect.any(String) }))

    const listed = await client.ok('list_proposals', { status: 'pending' })
    expect(listed.proposals.map((p: { id: string }) => p.id)).toEqual([changes2.proposalId, reading.proposalId, plan.proposalId])
    expect(listed.proposals[0]).toEqual(expect.objectContaining({ kind: 'changes', changes: 1, summary: 'Dos.' }))
    expect(listed.proposals[0].bundle).toBeUndefined()
    const detail = await client.ok('get_proposal', { id: plan.proposalId })
    expect(detail.bundle.routines).toHaveLength(2)
    expect(detail.createdAt).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/)
  })

  it('stops at 30 proposals in 24 hours, counting all three tools', async () => {
    await fillLimit('propose', 29)
    expect((await client.call('report_no_change', { reading: 'Todo bien.' })).isError).toBe(false)
    for (const [name, args] of [['propose_plan', BUNDLE], ['propose_changes', { summary: 'x', changes: [change()] }], ['report_no_change', { reading: 'x' }]] as const) {
      const result = await client.call(name, args)
      expect(result.isError, name).toBe(true)
      expect(result.text).toContain('at most 30 proposals per 24 hours')
    }
    expect(await listProposals(env.DB)).toHaveLength(1)
  })
})
