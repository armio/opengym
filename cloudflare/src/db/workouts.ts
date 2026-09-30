import { parseJsonObject, type JsonObject } from '../lib/json'
import { upsertStatements, type RowTable, type WriteMode } from './upsert'

/** A workout as the sync protocol carries it (contract §3.2). `data` is null for a tombstone. */
export interface WorkoutItem {
  id: string
  d: string
  start: number | null
  routineId: string | null
  data: JsonObject | null
  deleted: boolean
  updatedAt: number
}

export interface WorkoutRecord extends WorkoutItem {
  seq: number
}

/** A finished workout that has not been deleted. */
export interface StoredWorkout {
  id: string
  d: string
  start: number | null
  routineId: string | null
  data: JsonObject
  updatedAt: number
}

export interface WorkoutRow {
  id: string
  d: string
  start: number | null
  routine_id: string | null
  data: string | null
  deleted: number
  updated_at: number
  seq: number
}

export const WORKOUT_COLUMNS = 'id, d, start, routine_id, data, deleted, updated_at, seq'

export function toWorkoutRecord(row: WorkoutRow): WorkoutRecord {
  return {
    id: row.id,
    d: row.d,
    start: row.start,
    routineId: row.routine_id,
    data: row.deleted ? null : parseJsonObject(row.data),
    deleted: row.deleted === 1,
    updatedAt: row.updated_at,
    seq: row.seq,
  }
}

function toStoredWorkout(row: WorkoutRow): StoredWorkout {
  return { id: row.id, d: row.d, start: row.start, routineId: row.routine_id, data: parseJsonObject(row.data), updatedAt: row.updated_at }
}

const workoutTable: RowTable<WorkoutItem> = {
  table: 'workouts',
  key: 'id',
  columns: ['id', 'd', 'start', 'routine_id', 'data', 'deleted', 'updated_at'],
  values: w => [w.id, w.d, w.start, w.routineId, w.deleted || !w.data ? null : JSON.stringify(w.data), w.deleted ? 1 : 0, w.updatedAt],
}

/** Upserts workouts; must run after `bumpSeq` in the same batch. */
export function upsertWorkouts(db: D1Database, items: readonly WorkoutItem[], mode: WriteMode): D1PreparedStatement[] {
  return upsertStatements(db, workoutTable, items, mode)
}

export interface WorkoutQuery {
  /** Inclusive 'YYYY-MM-DD' bounds on `d`. */
  from?: string
  to?: string
  limit?: number
  /** `asc` (default) is `(d, start)` order; `desc` returns the newest first. */
  order?: 'asc' | 'desc'
}

/**
 * Non-deleted workouts ordered by `(d, start)` (engine-Q6). A null `start` sorts first within its
 * day; the app and the importer always store one.
 */
export async function listWorkouts(db: D1Database, query: WorkoutQuery = {}): Promise<StoredWorkout[]> {
  const where = ['deleted = 0']
  const params: unknown[] = []
  if (query.from) {
    where.push('d >= ?')
    params.push(query.from)
  }
  if (query.to) {
    where.push('d <= ?')
    params.push(query.to)
  }
  const direction = query.order === 'desc' ? 'DESC' : 'ASC'
  let sql = `SELECT ${WORKOUT_COLUMNS} FROM workouts WHERE ${where.join(' AND ')} ORDER BY d ${direction}, start ${direction}, id ${direction}`
  if (query.limit !== undefined) {
    sql += ' LIMIT ?'
    params.push(query.limit)
  }
  const { results } = await db.prepare(sql).bind(...params).all<WorkoutRow>()
  return results.map(toStoredWorkout)
}

/** Every non-deleted workout in `(d, start)` order. */
export function allWorkouts(db: D1Database): Promise<StoredWorkout[]> {
  return listWorkouts(db)
}

export async function getWorkout(db: D1Database, id: string): Promise<StoredWorkout | null> {
  const row = await db.prepare(`SELECT ${WORKOUT_COLUMNS} FROM workouts WHERE id = ? AND deleted = 0`).bind(id).first<WorkoutRow>()
  return row ? toStoredWorkout(row) : null
}
