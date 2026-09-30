import { describe, expect, it } from 'vitest'
import fixture from '../../../docs/flutter-cloudflare/fixtures/engine/dates.json'
import { addDays, mondayOf, sortWorkouts, streakWeeks, weekKey, weekdayOf, type Workout } from '../../src/engine'
import { runFixture, type FixtureFile } from './fixtures'

const file = fixture as unknown as FixtureFile

runFixture('dates.json', file, {
  weekKey: a => weekKey(a.date),
  streakWeeks: (a, clock) => streakWeeks(a.state, clock),
  sortWorkouts: a => sortWorkouts(a.workouts as Workout[], a.tz).map(w => w.id),
})

describe('calendar helpers', () => {
  it('weekday and day arithmetic are zone-independent', () => {
    expect(weekdayOf('2026-09-30')).toBe(3)
    expect(weekdayOf('2026-10-04')).toBe(0)
    expect(addDays('2026-03-28', 2)).toBe('2026-03-30')
    expect(addDays('2027-01-03', -7)).toBe('2026-12-27')
  })

  it('mondayOf is local noon of the Monday, across a DST change', () => {
    // 2026-10-25 is the last Sunday of October: Madrid leaves summer time that night.
    expect(new Date(mondayOf('2026-10-25', 'Europe/Madrid')).toISOString()).toBe('2026-10-19T10:00:00.000Z')
    expect(new Date(mondayOf('2026-10-26', 'Europe/Madrid')).toISOString()).toBe('2026-10-26T11:00:00.000Z')
    expect(new Date(mondayOf('2026-09-30', 'America/Los_Angeles')).toISOString()).toBe('2026-09-28T19:00:00.000Z')
  })

  it('keeps Monday to Sunday in one week, sampled over four centuries', () => {
    // Monday..Sunday of one ISO week share a key, and consecutive samples never do.
    let day = '1996-12-30'
    let previous = ''
    for (let i = 0; i < 1600; i++) {
      const key = weekKey(day)
      expect(key).not.toBe(previous)
      for (let j = 1; j < 7; j++) expect(weekKey(addDays(day, j))).toBe(key)
      previous = key
      day = addDays(day, 7 * 13)
    }
  })
})
