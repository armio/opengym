import { describe, expect, it } from 'vitest'
import { Catalog, customExercisesOf, foldText, LIBRARY, LIBRARY_BY_ID, normalizeCustomExercise } from '../src/catalog/library'

const customs = customExercisesOf({
  customEx: [
    { id: 'cmuo9zz12abc', n: 'Nordic curl', bp: 'upper legs', desc: 'Con banda', tg: '', eq: 'custom', custom: true },
    { id: 'kx2plan0cust', n: 'Sled sprint', bp: 'cardio' },
    { n: 'no id' },
  ],
})
const catalog = new Catalog(customs)

describe('library index', () => {
  it('indexes the 1324 exercises by string id', () => {
    expect(LIBRARY).toHaveLength(1324)
    expect(LIBRARY_BY_ID.get('0025')?.n).toBe('barbell bench press')
    expect(catalog.get('0025')).toEqual(
      expect.objectContaining({ name: 'barbell bench press', bodyPart: 'chest', bodyPart_es: 'pecho', equipment: 'barbell', custom: false }),
    )
    expect(catalog.get('0025')!.instructions_es.length).toBeGreaterThan(0)
  })
})

describe('custom exercises', () => {
  it('normalises every custom exercise to the data-B3 shape, keeping unknown keys', () => {
    expect(normalizeCustomExercise({ id: 'x1', n: 'Curl', bp: 'upper arms', extra: 1 })).toEqual({
      id: 'x1', n: 'Curl', bp: 'upper arms', desc: '', tg: '', eq: 'custom', custom: true, extra: 1,
    })
    expect(normalizeCustomExercise({ n: 'no id' })).toBeNull()
    expect(customs.map(c => c.id)).toEqual(['cmuo9zz12abc', 'kx2plan0cust'])
  })

  it('merges customs first and resolves their modes by body part', () => {
    expect(catalog.exercises[0]!.id).toBe('cmuo9zz12abc')
    expect(catalog.get('kx2plan0cust')).toEqual(expect.objectContaining({ custom: true, equipment: 'custom', bodyPart_es: 'cardio' }))
    expect(catalog.modeOf({ id: 'kx2plan0cust' })).toBe('cardio')
    expect(catalog.modeOf({ id: '0685' })).toBe(LIBRARY_BY_ID.get('0685')!.bp === 'cardio' ? 'cardio' : 'reps')
    expect(catalog.modeOf({ id: '0025', mode: 'time' })).toBe('time')
    expect(catalog.modeOf({ id: 'unknown' })).toBe('reps')
  })

  it('never lets a custom exercise shadow a library id', () => {
    const shadow = new Catalog([normalizeCustomExercise({ id: '0025', n: 'Fake', bp: 'cardio' })!])
    expect(shadow.get('0025')?.name).toBe('barbell bench press')
  })
})

describe('search', () => {
  it('folds case and accents', () => {
    expect(foldText('  Pectorales  ÉXITO ')).toBe('pectorales exito')
  })

  it('matches English names and Spanish labels, customs first, best name matches first', () => {
    expect(catalog.search({ query: 'Barbell Bench Press', limit: 5 })[0]!.id).toBe('0025')
    const bench = catalog.search({ query: 'bench press', limit: 5 })
    expect(bench.every(e => foldText(e.name).includes('bench press'))).toBe(true)

    const spanish = catalog.search({ query: 'pecho mancuerna', limit: 100 })
    expect(spanish.length).toBeGreaterThan(0)
    expect(spanish.every(e => e.bodyPart === 'chest' && e.equipment === 'dumbbell')).toBe(true)

    const accent = catalog.search({ query: 'cuadriceps', limit: 3 })
    expect(accent.length).toBe(3)

    const nordic = catalog.search({ query: 'curl', limit: 3 })
    expect(nordic[0]!.id).toBe('cmuo9zz12abc')
  })

  it('filters by body part, target and equipment in either language', () => {
    const chest = catalog.search({ bodyPart: 'Pecho', limit: 100 })
    expect(chest.length).toBe(100)
    expect(chest.every(e => e.bodyPart === 'chest')).toBe(true)
    expect(catalog.search({ bodyPart: 'chest', limit: 100 })).toEqual(chest)

    const lats = catalog.search({ target: 'lats', equipment: ['cable'], limit: 100 })
    expect(lats.length).toBeGreaterThan(0)
    expect(lats.every(e => e.target === 'lats' && e.equipment === 'cable')).toBe(true)

    const cardio = catalog.search({ bodyPart: 'cardio', equipment: ['barbell'], limit: 100 })
    expect(cardio[0]!.id).toBe('kx2plan0cust')
    expect(cardio.slice(1).every(e => e.equipment === 'barbell')).toBe(true)
  })

  it('defaults to 25 results and caps at 100', () => {
    expect(catalog.search()).toHaveLength(25)
    expect(catalog.search({ limit: 1000 })).toHaveLength(100)
  })
})
