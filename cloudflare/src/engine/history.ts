import { weekdayOf } from './dates'
import type { ExerciseConfig, ExerciseIndex, Mode, Routine, SetLog, TrainingState, Workout, WorkoutEntry, WorkoutLog } from './types'

/** Port of frontend/src/lib/history.js (engine.md §2) — the parts the Worker reads. */

export function isCardio(catalog: ExerciseIndex, id: unknown): boolean {
  return typeof id === 'string' && catalog.get(id)?.bodyPart === 'cardio'
}

/** How an exercise is logged: an explicit valid mode wins, else cardio by body part, else reps. */
export function modeOf(catalog: ExerciseIndex, cfg: { readonly id?: unknown; readonly mode?: unknown } | null | undefined): Mode {
  const mode = cfg?.mode
  if (mode === 'reps' || mode === 'time' || mode === 'cardio') return mode
  return isCardio(catalog, cfg?.id) ? 'cardio' : 'reps'
}

/** The mode a logged entry was recorded in: its stored target, with the entry's id merged in. */
export function entryModeOf(catalog: ExerciseIndex, entry: WorkoutEntry): Mode {
  return modeOf(catalog, { ...(entry.target ?? {}), id: entry.id })
}

export type EffortKind = 'rir' | 'rpe'

export const EFFORT = {
  rir: { f: 'rir', hd: 'RIR', step: 0.5, min: 0, max: 10 },
  rpe: { f: 'rpe', hd: 'RPE', step: 0.5, min: 6, max: 10 },
} as const

export interface EffortSettings {
  readonly effort?: unknown
  readonly showRir?: unknown
}

/** The scale a profile logs; an explicit 'none' beats the legacy `showRir` flag. */
export function effortOf(settings: EffortSettings | null | undefined): EffortKind | 'none' {
  const effort = settings?.effort
  if (effort === 'none' || effort === 'rir' || effort === 'rpe') return effort
  return settings?.showRir ? 'rir' : 'none'
}

export interface LastEntry {
  readonly d: string
  readonly sets: readonly SetLog[]
  readonly target: ExerciseConfig | null
}

/** The most recent session of an exercise with a done set: its date, done sets and target. */
export function lastEntryFor(S: WorkoutLog, exId: string): LastEntry | null {
  const workouts = S.workouts ?? []
  for (let i = workouts.length - 1; i >= 0; i--) {
    const workout = workouts[i]!
    const entry = workout.entries.find(e => e.id === exId)
    if (entry && entry.sets.some(s => s.done)) {
      return { d: workout.d, sets: entry.sets.filter(s => s.done), target: entry.target || null }
    }
  }
  return null
}

/**
 * The heaviest load ever handled: done sets' `w` and confirmed `topW`, over entries logged in
 * reps mode only (engine-Q5 — a weighted hold or a cardio set is not a load record).
 */
export function bestWeightFor(S: TrainingState, exId: string): number {
  let best = 0
  for (const workout of S.workouts ?? []) {
    for (const entry of workout.entries) {
      if (entry.id !== exId || entryModeOf(S.catalog, entry) !== 'reps') continue
      for (const s of entry.sets) if (s.done && (s.w ?? 0) > best) best = s.w!
      if (entry.topW && entry.topW > best) best = entry.topW
    }
  }
  return best
}

/**
 * The heaviest done set of every exercise over reps-mode entries, in one pass (engine-Q5; unlike
 * `bestWeightFor` it ignores `topW`). This is get_overview's `best` and the cap on weights Claude
 * proposes. Exercises never loaded are absent.
 */
export function heaviestDoneSets(S: TrainingState): Map<string, number> {
  const best = new Map<string, number>()
  for (const workout of S.workouts ?? []) {
    for (const entry of workout.entries) {
      if (entryModeOf(S.catalog, entry) !== 'reps') continue
      for (const s of entry.sets) {
        if (s.done && (s.w ?? 0) > (best.get(entry.id) ?? 0)) best.set(entry.id, s.w!)
      }
    }
  }
  return best
}

/** The plan and schedule docs merged: what decides which routine a date trains. */
export interface PlanView<R extends Pick<Routine, 'id'> = Pick<Routine, 'id'>> {
  readonly routines?: readonly R[]
  readonly week?: Readonly<Record<string, string | null | undefined>>
  readonly dayPlan?: Readonly<Record<string, string | null | undefined>>
}

/**
 * The routine id a date trains: a per-date override ('rest' or an existing routine), else the
 * weekly plan. The week may still hold the id of a deleted routine; see `effectiveRoutine`.
 */
export function effectiveRoutineId(plan: PlanView, iso: string): string | null {
  const override = plan.dayPlan?.[iso]
  if (override === 'rest') return null
  if (override && (plan.routines ?? []).some(r => r.id === override)) return override
  return plan.week?.[weekdayOf(iso)] || null
}

export function effectiveRoutine<R extends Pick<Routine, 'id'>>(plan: PlanView<R>, iso: string): R | null {
  const id = effectiveRoutineId(plan, iso)
  return id ? (plan.routines ?? []).find(r => r.id === id) ?? null : null
}

/** Σ w × r over done sets; timed and cardio sets add nothing. */
export function workoutVolume(workout: Pick<Workout, 'entries'>): number {
  let volume = 0
  for (const entry of workout.entries) for (const s of entry.sets) if (s.done) volume += (s.w || 0) * (s.r || 0)
  return volume
}

export function setsDone(workout: Pick<Workout, 'entries'>): number {
  let n = 0
  for (const entry of workout.entries) for (const s of entry.sets) if (s.done) n++
  return n
}
