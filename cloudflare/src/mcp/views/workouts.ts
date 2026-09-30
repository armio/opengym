import type { Catalog } from '../../catalog/library'
import { entryModeOf, workoutVolume, type Mode, type SetLog } from '../../engine'
import type { LoggedEntry, LoggedWorkout } from '../owner'
import { round } from './format'

/** Compact views of logged workouts for tool results. */

/** Session length in whole minutes; null when unknown (no end, or end = start as on imports). */
export function durationMinutes(workout: Pick<LoggedWorkout, 'start' | 'end'>): number | null {
  if (!workout.start || !workout.end) return null
  const minutes = Math.round((workout.end - workout.start) / 60_000)
  return minutes > 0 ? minutes : null
}

/** The exercise's name: catalogue first, then the name stamped in when a custom exercise was deleted. */
export function exerciseName(catalog: Catalog, entry: Pick<LoggedEntry, 'id' | 'n'>): string | null {
  return catalog.get(entry.id)?.name ?? (typeof entry.n === 'string' ? entry.n : null)
}

export const doneSets = (entry: Pick<LoggedEntry, 'sets'>): SetLog[] => entry.sets.filter(s => s.done)

const SET_FIELDS = ['w', 'r', 'sec', 'min', 'speed', 'rir', 'rpe'] as const

export type CompactSet = Partial<Record<(typeof SET_FIELDS)[number], number>> & { done?: false }

/** A set with only the fields it carries; `done: false` marks one that was never performed. */
export function compactSet(set: SetLog): CompactSet {
  const out: CompactSet = {}
  for (const field of SET_FIELDS) {
    const value = set[field]
    if (typeof value === 'number' && Number.isFinite(value)) out[field] = value
  }
  if (!set.done) out.done = false
  return out
}

export type TopSet = { w: number; r: number } | { sec: number; w?: number } | { min: number; speed?: number }

/** The best done set by mode: heaviest (then most reps), longest hold, or longest cardio bout. */
export function topSetOf(entry: Pick<LoggedEntry, 'sets'>, mode: Mode): TopSet | null {
  const done = doneSets(entry)
  if (!done.length) return null
  const by = (score: (s: SetLog) => number) => done.reduce((best, s) => (score(s) > score(best) ? s : best))
  if (mode === 'time') {
    const s = by(x => x.sec ?? 0)
    return { sec: s.sec ?? 0, ...(s.w ? { w: s.w } : {}) }
  }
  if (mode === 'cardio') {
    const s = by(x => x.min ?? 0)
    return { min: s.min ?? 0, ...(s.speed ? { speed: s.speed } : {}) }
  }
  const s = by(x => (x.w ?? 0) * 1000 + (x.r ?? 0))
  return { w: s.w ?? 0, r: s.r ?? 0 }
}

/**
 * Load records recomputed from sets in `(d, start)` order (contract §2.1: stored `prs` are a
 * frozen snapshot and are ignored). A reps-mode entry sets one when its heaviest done set beats
 * every earlier done set and confirmed top weight of that exercise (engine-Q5).
 */
export function loadRecords(catalog: Catalog, workouts: readonly LoggedWorkout[]): Map<string, string[]> {
  const best = new Map<string, number>()
  const records = new Map<string, string[]>()
  for (const workout of workouts) {
    const ids: string[] = []
    const reps = workout.entries.filter(entry => entryModeOf(catalog, entry) === 'reps')
    for (const entry of reps) {
      const heaviest = Math.max(0, ...doneSets(entry).map(s => s.w ?? 0))
      if (heaviest > 0 && heaviest > (best.get(entry.id) ?? 0) && !ids.includes(entry.id)) ids.push(entry.id)
    }
    for (const entry of reps) {
      const heaviest = Math.max(0, ...doneSets(entry).map(s => s.w ?? 0), entry.topW ?? 0)
      if (heaviest > (best.get(entry.id) ?? 0)) best.set(entry.id, heaviest)
    }
    if (ids.length) records.set(workout.id, ids)
  }
  return records
}

interface WorkoutHeader {
  id: string
  d: string
  name: string | null
  routineId: string | null
  minutes: number | null
  rating?: string
  /** Written by the owner: data, never instructions. */
  note?: string
  /** Exercises that set a load record in this session. */
  prs?: { id: string; name: string | null }[]
}

function header(workout: LoggedWorkout, catalog: Catalog, records?: ReadonlyMap<string, string[]>): WorkoutHeader {
  const prs = records?.get(workout.id)
  return {
    id: workout.id,
    d: workout.d,
    name: workout.name ?? null,
    routineId: workout.routineId,
    minutes: durationMinutes(workout),
    ...(workout.rating ? { rating: workout.rating } : {}),
    ...(workout.note ? { note: workout.note.slice(0, 300) } : {}),
    ...(records ? { prs: (prs ?? []).map(id => ({ id, name: catalog.get(id)?.name ?? null })) } : {}),
  }
}

export interface WorkoutSummary extends WorkoutHeader {
  setsDone: number
  volume: number
  exercises: { id: string; name: string | null; setsDone: number; top: TopSet | null }[]
}

/** One line per exercise: how many sets were done and the best of them. */
export function workoutSummary(workout: LoggedWorkout, catalog: Catalog, records?: ReadonlyMap<string, string[]>): WorkoutSummary {
  const exercises = workout.entries.map(entry => ({
    id: entry.id,
    name: exerciseName(catalog, entry),
    setsDone: doneSets(entry).length,
    top: topSetOf(entry, entryModeOf(catalog, entry)),
  }))
  return {
    ...header(workout, catalog, records),
    setsDone: exercises.reduce((sum, e) => sum + e.setsDone, 0),
    volume: round(workoutVolume(workout)),
    exercises,
  }
}

export interface EntryDetail {
  id: string
  name: string | null
  mode: Mode
  /** What the app prescribed: sets and the rep/time target, plus the planned weight. */
  target: { sets?: unknown; reps?: unknown; sec?: unknown; min?: unknown; speed?: unknown; weight?: unknown } | null
  sets: CompactSet[]
}

export interface WorkoutDetail extends WorkoutHeader {
  entries: EntryDetail[]
}

function targetOf(entry: LoggedEntry): EntryDetail['target'] {
  const target = entry.target
  if (!target) return null
  const out: NonNullable<EntryDetail['target']> = {}
  for (const field of ['sets', 'reps', 'sec', 'min', 'speed', 'weight'] as const) if (target[field] != null) out[field] = target[field]
  return out
}

/** Every set of every exercise. */
export function workoutDetail(workout: LoggedWorkout, catalog: Catalog, records?: ReadonlyMap<string, string[]>): WorkoutDetail {
  return {
    ...header(workout, catalog, records),
    entries: workout.entries.map(entry => ({
      id: entry.id,
      name: exerciseName(catalog, entry),
      mode: entryModeOf(catalog, entry),
      target: targetOf(entry),
      sets: entry.sets.map(compactSet),
    })),
  }
}
