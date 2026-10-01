import { DAY_MS } from '../lib/time'
import { mondayOf, startOf, weekKey } from './dates'
import { effortOf, type EffortKind, type EffortSettings } from './history'
import type { Clock, SetLog, Workout, WorkoutEntry, WorkoutLog } from './types'

/**
 * Port of frontend/src/lib/effort.js (engine.md §6). Everything aggregates in RIR (it has a real
 * zero) and converts back for display. Windows count back from `clock.now`; a date-only workout
 * sits at local noon of its date (engine-Q7).
 */

/** RIR ≤ 3 is a hard set. */
export const HARD_RIR = 3
/** Fewer rated sets than this and averages are null. */
export const MIN_RATED = 5
/** Histogram bins 0, 1, 2, 3 and a "4+" tail. */
export const BUCKETS = 4

/** A set's effort in RIR (RPE 8 = RIR 2), or null when it was never rated. 0 is a rating. */
export function rirOf(s: SetLog | null | undefined): number | null {
  if (!s) return null
  if (s.rir != null) return s.rir
  return s.rpe != null ? 10 - s.rpe : null
}

export function toScale(kind: EffortKind, rir: number | null | undefined): number | null {
  return rir == null ? null : Math.round((kind === 'rpe' ? 10 - rir : rir) * 10) / 10
}

export const isHardSet = (s: SetLog): boolean => {
  const r = rirOf(s)
  return r != null && r <= HARD_RIR
}

function forEachDoneSet(S: WorkoutLog, fn: (s: SetLog, workout: Workout, entry: WorkoutEntry) => void): void {
  for (const workout of S.workouts ?? []) {
    for (const entry of workout.entries ?? []) for (const s of entry.sets ?? []) if (s.done) fn(s, workout, entry)
  }
}

/** Done sets of workouts inside the last `days` days (0 = everything). */
function forEachDoneSetIn(S: WorkoutLog, days: number, clock: Clock, fn: (s: SetLog, workout: Workout) => void): void {
  const cutoff = clock.now - days * DAY_MS
  for (const workout of S.workouts ?? []) {
    if (days && !(startOf(workout, clock.tz) > cutoff)) continue
    for (const entry of workout.entries ?? []) for (const s of entry.sets ?? []) if (s.done) fn(s, workout)
  }
}

/** The scale to label aggregates with: the profile's own, else whichever its history uses more. */
export function displayScale(S: EffortSettings & WorkoutLog): EffortKind {
  const kind = effortOf(S)
  if (kind !== 'none') return kind
  let rir = 0
  let rpe = 0
  forEachDoneSet(S, s => {
    if (s.rir != null) rir++
    else if (s.rpe != null) rpe++
  })
  return rpe > rir ? 'rpe' : 'rir'
}

export function avgRir(sets: readonly SetLog[] | null | undefined): number | null {
  const values = (sets ?? []).map(rirOf).filter((v): v is number => v != null)
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null
}

export interface EffortSummary {
  /** Done sets in the window. */
  readonly done: number
  /** Of those, the rated ones. */
  readonly rated: number
  readonly hard: number
  readonly avg: number | null
  /** The hard-set share of rated sets. */
  readonly hardPct: number | null
}

export function effortSummary(S: WorkoutLog, days: number, clock: Clock): EffortSummary {
  let done = 0
  let rated = 0
  let sum = 0
  let hard = 0
  forEachDoneSetIn(S, days, clock, s => {
    done++
    const r = rirOf(s)
    if (r == null) return
    rated++
    sum += r
    if (r <= HARD_RIR) hard++
  })
  return {
    done,
    rated,
    hard,
    avg: rated >= MIN_RATED ? sum / rated : null,
    hardPct: rated >= MIN_RATED ? hard / rated : null,
  }
}

/** Does any done set carry a rating? */
export function hasEffort(S: WorkoutLog): boolean {
  let any = false
  forEachDoneSet(S, s => {
    if (!any && rirOf(s) != null) any = true
  })
  return any
}

export interface EffortWeek {
  /** Local noon of the week's Monday (epoch ms). */
  readonly t: number
  readonly rir: number
  /** Rated sets. */
  readonly n: number
  /** Done sets. */
  readonly sets: number
}

/** Average RIR per ISO week with the week's set count; weeks with fewer than 2 rated sets are dropped. */
export function effortWeeks(S: WorkoutLog, days: number, clock: Clock): EffortWeek[] {
  const weeks = new Map<string, { t: number; sum: number; n: number; sets: number }>()
  forEachDoneSetIn(S, days, clock, (s, workout) => {
    const key = weekKey(workout.d)
    let week = weeks.get(key)
    if (!week) weeks.set(key, (week = { t: mondayOf(workout.d, clock.tz), sum: 0, n: 0, sets: 0 }))
    week.sets++
    const r = rirOf(s)
    if (r != null) {
      week.sum += r
      week.n++
    }
  })
  return [...weeks.values()]
    .filter(week => week.n >= 2)
    .sort((a, b) => a.t - b.t)
    .map(week => ({ t: week.t, rir: week.sum / week.n, n: week.n, sets: week.sets }))
}

export interface EffortBin {
  readonly rir: number
  readonly tail: boolean
  readonly n: number
  readonly pct: number
}

/** Rated sets binned by whole RIR steps, everything from 4 up in the tail. */
export function effortHistogram(S: WorkoutLog, days: number, clock: Clock): EffortBin[] {
  const bins: number[] = new Array(BUCKETS + 1).fill(0)
  let rated = 0
  forEachDoneSetIn(S, days, clock, s => {
    const r = rirOf(s)
    if (r == null) return
    rated++
    bins[Math.min(BUCKETS, Math.max(0, Math.floor(r)))]!++
  })
  return bins.map((n, i) => ({ rir: i, tail: i === BUCKETS, n, pct: rated ? n / rated : 0 }))
}
