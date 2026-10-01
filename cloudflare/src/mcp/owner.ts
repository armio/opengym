import { Catalog } from '../catalog/library'
import { getDocs, getExWeights, listProposals, listWorkouts, ownerTimeZone, type Docs, type ProposalDTO, type StoredWorkout, type WorkoutQuery } from '../db'
import { sortWorkouts, type Clock, type PlannedExercise, type SetLog, type TrainingState, type Workout, type WorkoutEntry } from '../engine'
import { isPlainObject, type JsonObject } from '../lib/json'
import { localDate } from '../lib/time'

/**
 * Everything the MCP tools read about the owner, loaded from D1 and normalised once per call.
 * Stored JSON comes from many app versions and imports, so malformed items are dropped here and
 * the payload builders can trust the shapes.
 */

export type Unit = 'kg' | 'lb'

export interface PlanRoutine {
  readonly id: string
  readonly name?: string
  readonly emoji?: unknown
  readonly prog?: string
  readonly ex: readonly PlannedExercise[]
}

/** The plan doc with malformed routines/exercises dropped and rest days removed from `week`. */
export interface Plan {
  readonly routines: readonly PlanRoutine[]
  /** Weekday '0'..'6' (0 = Sunday) → routine id; days without a routine are absent. */
  readonly week: Readonly<Record<string, string>>
}

export interface Owner {
  readonly clock: Clock
  /** The owner's local date. */
  readonly today: string
  readonly settings: JsonObject
  readonly unit: Unit
  /** The plan doc as read (see `readPlan`); validation, `before` values and the plan hash all use it. */
  readonly plan: Plan
  /** Per-date reschedules: 'YYYY-MM-DD' → routine id or 'rest'. */
  readonly dayPlan: Readonly<Record<string, string>>
  readonly athlete: JsonObject
  readonly coach: JsonObject
  /** The library plus the owner's custom exercises. */
  readonly catalog: Catalog
}

const hasId = (value: unknown): value is JsonObject & { id: string } =>
  isPlainObject(value) && typeof value.id === 'string' && value.id !== ''

function readRoutine(raw: JsonObject & { id: string }): PlanRoutine {
  const ex = (Array.isArray(raw.ex) ? raw.ex : []).filter(hasId) as unknown as PlannedExercise[]
  return {
    ...raw,
    id: raw.id,
    ...(typeof raw.name === 'string' ? { name: raw.name } : {}),
    ...(typeof raw.prog === 'string' && raw.prog ? { prog: raw.prog } : {}),
    ex,
  }
}

function stringMap(value: unknown, keyPattern: RegExp): Record<string, string> {
  if (!isPlainObject(value)) return {}
  return Object.fromEntries(Object.entries(value).filter((pair): pair is [string, string] => keyPattern.test(pair[0]) && typeof pair[1] === 'string' && pair[1] !== ''))
}

export function readPlan(planDoc: JsonObject): Plan {
  return {
    routines: (Array.isArray(planDoc.routines) ? planDoc.routines : []).filter(hasId).map(readRoutine),
    week: stringMap(planDoc.week, /^[0-6]$/),
  }
}

export function routineById(plan: Plan, id: string | null | undefined): PlanRoutine | undefined {
  return id ? plan.routines.find(routine => routine.id === id) : undefined
}

/** The owner's view of the docs at an instant; `loadOwner` reads both from D1. */
export function ownerFromDocs(docs: Docs, clock: Clock): Owner {
  const settings = docs.settings.data
  const planDoc = docs.plan.data
  return {
    clock,
    today: localDate(clock.now, clock.tz),
    settings,
    unit: settings.unit === 'lb' ? 'lb' : 'kg',
    plan: readPlan(planDoc),
    dayPlan: stringMap(docs.schedule.data.dayPlan, /^\d{4}-\d{2}-\d{2}$/),
    athlete: docs.athlete.data,
    coach: docs.coach.data,
    catalog: Catalog.forPlan(planDoc),
  }
}

export async function loadOwner(db: D1Database, now = Date.now()): Promise<Owner> {
  const [docs, tz] = await Promise.all([getDocs(db), ownerTimeZone(db)])
  return ownerFromDocs(docs, { now, tz })
}

/* ------------------------------------------------------------------ workouts */

export interface LoggedEntry extends WorkoutEntry {
  /** Exercise name stamped in when a custom exercise was deleted. */
  readonly n?: string
}

/** A finished workout as the tools read it. */
export interface LoggedWorkout extends Workout {
  readonly id: string
  readonly routineId: string | null
  readonly name?: string
  readonly rating?: string
  readonly note?: string
  readonly entries: readonly LoggedEntry[]
}

function readEntry(raw: JsonObject & { id: string }): LoggedEntry {
  const sets = (Array.isArray(raw.sets) ? raw.sets : []).filter(isPlainObject) as SetLog[]
  const target = isPlainObject(raw.target) ? raw.target : null
  return { ...raw, id: raw.id, sets, target }
}

export function toLoggedWorkout(row: StoredWorkout): LoggedWorkout {
  const data = row.data
  const optionalString = (key: string) => (typeof data[key] === 'string' && data[key] !== '' ? { [key]: data[key] as string } : {})
  return {
    ...data,
    id: row.id,
    d: row.d,
    start: row.start ?? (typeof data.start === 'number' ? data.start : null),
    end: typeof data.end === 'number' ? data.end : null,
    routineId: row.routineId,
    ...optionalString('name'),
    ...optionalString('rating'),
    ...optionalString('note'),
    entries: (Array.isArray(data.entries) ? data.entries : []).filter(hasId).map(readEntry),
  }
}

/** Non-deleted workouts in `(d, start)` order, a date-only workout at local noon (engine-Q6/Q7). */
export async function loadWorkouts(db: D1Database, tz: string, query: Omit<WorkoutQuery, 'order'> = {}): Promise<LoggedWorkout[]> {
  return sortWorkouts((await listWorkouts(db, query)).map(toLoggedWorkout), tz)
}

/** The engine's view of the owner's training: catalogue, ordered history and unit, plus `ex_weights`. */
export interface Training extends TrainingState {
  readonly workouts: readonly LoggedWorkout[]
  /** The confirmed working weight per exercise id (the `ex_weights` rows). */
  readonly workingWeights: Readonly<Record<string, { readonly w: number; readonly d: string | null } | undefined>>
}

export async function loadTraining(db: D1Database, owner: Owner): Promise<Training> {
  const [workouts, workingWeights] = await Promise.all([loadWorkouts(db, owner.clock.tz), getExWeights(db)])
  return { catalog: owner.catalog, workouts, unit: owner.unit, workingWeights }
}

/* ------------------------------------------------------------------ proposals */

/**
 * How many of the newest proposals the analysis tools read: far more than the 10 recent
 * decisions, the pending ones (which expire within 14 days) and the last review need. Older
 * declined changes also live in the coach log.
 */
export const RECENT_PROPOSALS = 100

/** The newest proposals, newest first. */
export function loadRecentProposals(db: D1Database): Promise<ProposalDTO[]> {
  return listProposals(db, { limit: RECENT_PROPOSALS })
}
