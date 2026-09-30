import { upsertStatements, type RowTable, type WriteMode } from './upsert'

/** A body-weight entry as the sync protocol carries it; `w`/`t` are null for a tombstone. */
export interface BodyweightItem {
  d: string
  w: number | null
  t: number | null
  deleted: boolean
  updatedAt: number
}

export interface BodyweightRecord extends BodyweightItem {
  seq: number
}

export interface BodyweightEntry {
  d: string
  w: number
  t: number | null
}

export interface BodyweightRow {
  d: string
  w: number | null
  t: number | null
  deleted: number
  updated_at: number
  seq: number
}

export const BODYWEIGHT_COLUMNS = 'd, w, t, deleted, updated_at, seq'

export function toBodyweightRecord(row: BodyweightRow): BodyweightRecord {
  const deleted = row.deleted === 1
  return { d: row.d, w: deleted ? null : row.w, t: deleted ? null : row.t, deleted, updatedAt: row.updated_at, seq: row.seq }
}

const bodyweightTable: RowTable<BodyweightItem> = {
  table: 'bodyweight',
  key: 'd',
  columns: ['d', 'w', 't', 'deleted', 'updated_at'],
  values: b => [b.d, b.deleted ? null : b.w, b.deleted ? null : b.t, b.deleted ? 1 : 0, b.updatedAt],
}

/** Upserts body-weight entries; must run after `bumpSeq` in the same batch. */
export function upsertBodyweight(db: D1Database, items: readonly BodyweightItem[], mode: WriteMode): D1PreparedStatement[] {
  return upsertStatements(db, bodyweightTable, items, mode)
}

/** Non-deleted entries in date order, optionally within inclusive 'YYYY-MM-DD' bounds. */
export async function listBodyweight(db: D1Database, range: { from?: string; to?: string } = {}): Promise<BodyweightEntry[]> {
  const where = ['deleted = 0']
  const params: string[] = []
  if (range.from) {
    where.push('d >= ?')
    params.push(range.from)
  }
  if (range.to) {
    where.push('d <= ?')
    params.push(range.to)
  }
  const { results } = await db
    .prepare(`SELECT d, w, t FROM bodyweight WHERE ${where.join(' AND ')} ORDER BY d`)
    .bind(...params)
    .all<{ d: string; w: number; t: number | null }>()
  return results.map(row => ({ d: row.d, w: row.w, t: row.t }))
}
