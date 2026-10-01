import { beforeAll, describe, expect, it } from 'vitest'
import { seedDoc } from '../helpers'
import { freshOwner, McpClient } from './client'

let client: McpClient

beforeAll(async () => {
  ;({ client } = await freshOwner())
  await seedDoc('plan', {
    routines: [{ id: 'r1', name: 'Pierna', emoji: '🦵', ex: [{ id: '0043', sets: 4, reps: 5 }, { id: 'cx-nordic', sets: 3, reps: 6 }] }],
    week: {},
    customEx: [{ id: 'cx-nordic', n: 'Nordic curl', bp: 'upper legs', desc: 'De rodillas, baja despacio.', tg: '', eq: 'custom', custom: true }],
  })
})

type Found = { id: string; name: string; bodyPart: string; target: string | null; equipment: string; custom: boolean }

describe('search_exercises', () => {
  it('matches Spanish body-part and muscle labels, accents optional', async () => {
    const chest: Found[] = (await client.ok('search_exercises', { bodyPart: 'pecho' })).exercises
    expect(chest).toHaveLength(25)
    expect(chest.every(e => e.bodyPart === 'chest')).toBe(true)

    for (const target of ['cuádriceps', 'CUADRICEPS']) {
      const quads: Found[] = (await client.ok('search_exercises', { target, limit: 100 })).exercises
      expect(quads.length, target).toBe(44)
      expect(quads.every(e => e.target === 'quads'), target).toBe(true)
    }
  })

  it('combines free text, muscle and equipment in either language', async () => {
    const found: Found[] = (await client.ok('search_exercises', { query: 'press barra', limit: 100 })).exercises
    expect(found.map(e => e.id)).toContain('0025')
    // "barra" as free text also finds "barra EZ", "barra olímpica" and "barra hexagonal".
    expect(found.every(e => /barbell|trap bar/.test(e.equipment) && e.name.includes('press'))).toBe(true)

    const squats: Found[] = (await client.ok('search_exercises', { query: 'squat', target: 'glúteos', equipment: ['barra', 'smith machine'], limit: 100 })).exercises
    expect(squats.map(e => e.id)).toContain('0043')
    expect(squats.every(e => e.target === 'glutes' && ['barbell', 'smith machine'].includes(e.equipment))).toBe(true)
  })

  it('lists the owner\'s custom exercises first', async () => {
    const legs: Found[] = (await client.ok('search_exercises', { bodyPart: 'piernas' })).exercises
    expect(legs[0]).toEqual({ id: 'cx-nordic', name: 'Nordic curl', bodyPart: 'upper legs', target: null, equipment: 'custom', custom: true })
    expect(legs.slice(1).every(e => !e.custom)).toBe(true)
  })
})

describe('get_exercise', () => {
  it('returns the full record in English and Spanish with its default mode', async () => {
    const bench = await client.ok('get_exercise', { id: '0025' })
    expect(bench).toEqual(expect.objectContaining({
      id: '0025', name: 'barbell bench press', custom: false,
      bodyPart: 'chest', bodyPart_es: 'pecho', target: 'pectorals', target_es: 'pectorales', equipment: 'barbell', equipment_es: 'barra',
      secondary: ['triceps', 'shoulders'], defaultMode: 'reps', policies: ['off', 'linear', 'greyskull', 'double'], inRoutines: [],
    }))
    expect(bench.instructions_es.length).toBeGreaterThan(2)
    expect(bench.secondary_es).toHaveLength(2)

    const run = await client.ok('get_exercise', { id: '0685' })
    expect(run).toEqual(expect.objectContaining({ bodyPart: 'cardio', defaultMode: 'cardio', policies: ['off'] }))

    const squat = await client.ok('get_exercise', { id: '0043' })
    expect(squat.inRoutines).toEqual([{ routineId: 'r1', routine: 'Pierna' }])
  })

  it('includes a custom exercise with its description, and rejects unknown ids', async () => {
    const nordic = await client.ok('get_exercise', { id: 'cx-nordic' })
    expect(nordic).toEqual(expect.objectContaining({ custom: true, bodyPart: 'upper legs', bodyPart_es: 'piernas', desc: 'De rodillas, baja despacio.', defaultMode: 'reps' }))
    const unknown = await client.call('get_exercise', { id: 'nope' })
    expect(unknown.isError).toBe(true)
    expect(unknown.text).toContain('search_exercises')
  })
})
