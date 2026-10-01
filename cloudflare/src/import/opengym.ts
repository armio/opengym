import { Catalog, normalizeCustomExercise, type CustomExercise } from '../catalog/library'
import type { BodyweightItem } from '../db/bodyweight'
import { defaultDocData, type DocWrite } from '../db/docs'
import type { ExWeightItem } from '../db/exWeights'
import type { WorkoutItem } from '../db/workouts'
import { byteLength, isPlainObject, type JsonObject } from '../lib/json'
import { MAX_WORKOUT_BYTES, ROW_ID } from '../lib/rules'
import { isIsoDate, localNoon } from '../lib/time'

/** Top-level keys of an openGym backup that do not belong to the settings doc. */
const NON_SETTINGS_KEYS = new Set([
  'bodyweight', 'routines', 'week', 'dayPlan', 'exWeights', 'workouts', 'active', 'customEx', 'coach', '_ts',
])


export interface MappedBackup {
  docs: DocWrite[]
  workouts: WorkoutItem[]
  bodyweight: BodyweightItem[]
  exWeights: ExWeightItem[]
  routineCount: number
  /**
   * Every workout id, body-weight date and working-weight id the file names, valid or not. A
   * replace import keeps these on the server: a row skipped as malformed must not be deleted.
   */
  keep: { workouts: string[]; bodyweight: string[]; exWeights: string[] }
  /** How many rows of each kind were skipped as malformed. */
  skipped: { workouts: number; bodyweight: number; exWeights: number }
}

function mentioned(list: unknown, key: 'id' | 'd'): string[] {
  if (!Array.isArray(list)) return []
  return list.flatMap(entry => (isPlainObject(entry) && typeof entry[key] === 'string' ? [entry[key] as string] : []))
}

/** True when `state` looks like an openGym `S` (contract §4.4). */
export function isOpenGymState(state: unknown): state is JsonObject {
  return isPlainObject(state) && Array.isArray(state.workouts) && Array.isArray(state.routines)
}

const objectOr = (value: unknown, fallback: JsonObject = {}): JsonObject => (isPlainObject(value) ? value : fallback)

function settingsFrom(state: JsonObject): JsonObject {
  const settings = defaultDocData('settings')
  for (const [key, value] of Object.entries(state)) if (!NON_SETTINGS_KEYS.has(key)) settings[key] = value
  settings.lang = 'es'
  return settings
}

function customExercisesFrom(state: JsonObject): CustomExercise[] {
  const list = Array.isArray(state.customEx) ? state.customEx : []
  return list.map(normalizeCustomExercise).filter((c): c is CustomExercise => c !== null)
}

/**
 * Stamps `id` and an explicit `mode` on every non-null entry target (engine-Q4), and gives a
 * workout without `start` the local noon of its date (engine-Q7).
 */
function normalizeWorkout(raw: JsonObject, catalog: Catalog, timeZone: string): JsonObject {
  const workout: JsonObject = { ...raw }
  if (typeof workout.start !== 'number') workout.start = localNoon(workout.d as string, timeZone)
  if (Array.isArray(workout.entries)) {
    workout.entries = workout.entries.map(entry => {
      if (!isPlainObject(entry) || !isPlainObject(entry.target)) return entry
      const target = { ...entry.target, id: entry.id }
      return { ...entry, target: { ...target, mode: catalog.modeOf(target) } }
    })
  }
  return workout
}

function workoutsFrom(state: JsonObject, catalog: Catalog, timeZone: string, now: number): WorkoutItem[] {
  const byId = new Map<string, WorkoutItem>()
  for (const raw of state.workouts as unknown[]) {
    if (!isPlainObject(raw) || typeof raw.id !== 'string' || !ROW_ID.test(raw.id) || !isIsoDate(raw.d)) continue
    const data = normalizeWorkout(raw, catalog, timeZone)
    if (byteLength(JSON.stringify(data)) > MAX_WORKOUT_BYTES) continue
    byId.set(raw.id, {
      id: raw.id,
      d: raw.d,
      start: data.start as number,
      routineId: typeof raw.routineId === 'string' ? raw.routineId : null,
      data,
      deleted: false,
      updatedAt: now,
    })
  }
  return [...byId.values()]
}

function bodyweightFrom(state: JsonObject, now: number): BodyweightItem[] {
  const byDate = new Map<string, BodyweightItem>()
  const list = Array.isArray(state.bodyweight) ? state.bodyweight : []
  for (const entry of list) {
    if (!isPlainObject(entry) || !isIsoDate(entry.d)) continue
    const w = entry.w
    if (typeof w !== 'number' || !Number.isFinite(w) || w <= 0) continue
    const t = typeof entry.t === 'number' && Number.isSafeInteger(entry.t) ? entry.t : null
    byDate.set(entry.d, { d: entry.d, w, t, deleted: false, updatedAt: now })
  }
  return [...byDate.values()]
}

function exWeightsFrom(state: JsonObject, now: number): ExWeightItem[] {
  const items: ExWeightItem[] = []
  for (const [id, value] of Object.entries(objectOr(state.exWeights))) {
    if (!ROW_ID.test(id) || !isPlainObject(value)) continue
    const w = value.w
    if (typeof w !== 'number' || !Number.isFinite(w) || w < 0) continue
    items.push({ id, w, d: isIsoDate(value.d) ? value.d : null, deleted: false, updatedAt: now })
  }
  return items
}

function coachFrom(state: JsonObject): JsonObject {
  const coach = objectOr(state.coach)
  return {
    log: Array.isArray(coach.log) ? coach.log : [],
    snapshots: Array.isArray(coach.snapshots) ? coach.snapshots : [],
    lastReview: coach.lastReview ?? null,
  }
}

function athleteFrom(state: JsonObject, now: number): JsonObject | null {
  const profile = objectOr(state.coach).profile
  if (!isPlainObject(profile)) return null
  return { ...defaultDocData('athlete'), ...profile, savedAt: now, updatedBy: 'import' }
}

/**
 * Maps an openGym backup `S` onto the port's docs and rows (contract §4.4). Invalid rows are
 * skipped; `active`, `_ts`, `coach.consent` and `coach.cadence` are dropped.
 */
export function mapOpenGymBackup(state: JsonObject, options: { now: number; timeZone: string }): MappedBackup {
  const { now, timeZone } = options
  const customEx = customExercisesFrom(state)
  const catalog = new Catalog(customEx)
  const routines = state.routines as unknown[]

  const docs: DocWrite[] = [
    { key: 'settings', data: settingsFrom(state), updatedAt: now },
    { key: 'plan', data: { routines, week: objectOr(state.week), customEx }, updatedAt: now },
    { key: 'schedule', data: { dayPlan: objectOr(state.dayPlan) }, updatedAt: now },
    { key: 'coach', data: coachFrom(state), updatedAt: now },
  ]
  const athlete = athleteFrom(state, now)
  if (athlete) docs.push({ key: 'athlete', data: athlete, updatedAt: now })

  const workouts = workoutsFrom(state, catalog, timeZone, now)
  const bodyweight = bodyweightFrom(state, now)
  const exWeights = exWeightsFrom(state, now)
  const keep = {
    workouts: [...new Set(mentioned(state.workouts, 'id'))],
    bodyweight: [...new Set(mentioned(state.bodyweight, 'd'))],
    exWeights: Object.keys(objectOr(state.exWeights)),
  }
  return {
    docs,
    workouts,
    bodyweight,
    exWeights,
    routineCount: routines.length,
    keep,
    skipped: {
      workouts: (state.workouts as unknown[]).length - workouts.length,
      bodyweight: (Array.isArray(state.bodyweight) ? state.bodyweight.length : 0) - bodyweight.length,
      exWeights: keep.exWeights.length - exWeights.length,
    },
  }
}
