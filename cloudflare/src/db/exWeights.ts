import { upsertStatements, type RowTable, type WriteMode } from './upsert'

/** A working weight as the sync protocol carries it (`id` is the exercise id). */
export interface ExWeightItem {
  id: string
  w: number | null
  d: string | null
  deleted: boolean
  updatedAt: number
}

export interface ExWeightRecord extends ExWeightItem {
  seq: number
}

export interface ExWeightRow {
  ex_id: string
  w: number | null
  d: string | null
  deleted: number
  updated_at: number
  seq: number
}

export const EX_WEIGHT_COLUMNS = 'ex_id, w, d, deleted, updated_at, seq'

export function toExWeightRecord(row: ExWeightRow): ExWeightRecord {
  const deleted = row.deleted === 1
  return { id: row.ex_id, w: deleted ? null : row.w, d: deleted ? null : row.d, deleted, updatedAt: row.updated_at, seq: row.seq }
}

const exWeightTable: RowTable<ExWeightItem> = {
  table: 'ex_weights',
  key: 'ex_id',
  columns: ['ex_id', 'w', 'd', 'deleted', 'updated_at'],
  values: x => [x.id, x.deleted ? null : x.w, x.deleted ? null : x.d, x.deleted ? 1 : 0, x.updatedAt],
}

/** Upserts working weights; must run after `bumpSeq` in the same batch. */
export function upsertExWeights(db: D1Database, items: readonly ExWeightItem[], mode: WriteMode): D1PreparedStatement[] {
  return upsertStatements(db, exWeightTable, items, mode)
}

/** The working-weight memory (`exWeights` of the original): exercise id → `{ w, d }`. */
export async function getExWeights(db: D1Database): Promise<Record<string, { w: number; d: string | null }>> {
  const { results } = await db
    .prepare('SELECT ex_id, w, d FROM ex_weights WHERE deleted = 0 ORDER BY ex_id')
    .all<{ ex_id: string; w: number; d: string | null }>()
  return Object.fromEntries(results.map(row => [row.ex_id, { w: row.w, d: row.d }]))
}
