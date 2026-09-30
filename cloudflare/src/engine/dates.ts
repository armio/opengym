import { DAY_MS, localDate, localNoon } from '../lib/time'
import type { Clock, Workout, WorkoutLog } from './types'

/*
 * Calendar arithmetic on 'YYYY-MM-DD' strings. The original did it on local Date objects; a
 * calendar date has the same weekday and ISO week in every zone, so UTC arithmetic gives the
 * same answers without depending on the Worker's zone.
 */

const noonUtc = (iso: string) => new Date(iso + 'T12:00:00Z')

const isoOfUtc = (date: Date) => date.toISOString().slice(0, 10)

/** 0 = Sunday … 6 = Saturday (JavaScript `getDay`). NaN for a malformed date. */
export function weekdayOf(iso: string): number {
  return noonUtc(iso).getUTCDay()
}

export function addDays(iso: string, days: number): string {
  const date = noonUtc(iso)
  date.setUTCDate(date.getUTCDate() + days)
  return isoOfUtc(date)
}

/** ISO-8601 week as "<week-year>-<week>", week not zero-padded (engine.md §3). */
export function weekKey(iso: string): string {
  const thursday = noonUtc(iso)
  thursday.setUTCDate(thursday.getUTCDate() - ((thursday.getUTCDay() + 6) % 7) + 3)
  const year = thursday.getUTCFullYear()
  const jan4 = new Date(Date.UTC(year, 0, 4))
  const week = 1 + Math.round(((thursday.getTime() - jan4.getTime()) / DAY_MS - 3 + ((jan4.getUTCDay() + 6) % 7)) / 7)
  return year + '-' + week
}

/** Local noon (epoch ms in `tz`) of the Monday of the ISO week containing `iso`. */
export function mondayOf(iso: string, tz: string): number {
  return localNoon(addDays(iso, -((weekdayOf(iso) + 6) % 7)), tz)
}

/**
 * Consecutive ISO weeks with at least one workout, counting back from the current week. An
 * empty current week does not break the streak (yet). Capped at 520 weeks.
 */
export function streakWeeks(S: WorkoutLog, clock: Clock): number {
  const workouts = S.workouts ?? []
  if (!workouts.length) return 0
  const weeks = new Set(workouts.map(w => weekKey(w.d)))
  const today = localDate(clock.now, clock.tz)
  let streak = 0
  for (let i = 0; i < 520; i++) {
    if (weeks.has(weekKey(addDays(today, -7 * i)))) streak++
    else if (i > 0) break
  }
  return streak
}

/** When a workout started; a date-only workout counts as local noon of its date (engine-Q7). */
export function startOf(workout: Pick<Workout, 'd' | 'start'>, tz: string): number {
  return workout.start || localNoon(workout.d, tz)
}

/**
 * Workouts in the order everything order-dependent reads them: `(d, start)` ascending, stable
 * (engine-Q6). Returns a new array.
 */
export function sortWorkouts<W extends Pick<Workout, 'd' | 'start'>>(workouts: readonly W[], tz: string): W[] {
  return workouts
    .map(workout => ({ workout, start: startOf(workout, tz) }))
    .sort((a, b) => (a.workout.d < b.workout.d ? -1 : a.workout.d > b.workout.d ? 1 : a.start - b.start))
    .map(item => item.workout)
}
