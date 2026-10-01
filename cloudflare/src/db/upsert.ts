import { SEQ } from './seq'

/**
 * How a row write resolves against the stored row:
 * - `lww`: per-item last-writer-wins on `updated_at`; ties keep the stored row (contract §3.2).
 * - `force`: always overwrite (import, reset), moving `updated_at` past the stored value so a
 *   device still holding the older copy loses the next LWW comparison.
 */
export type WriteMode = 'lww' | 'force'

export interface RowTable<T> {
  table: string
  /** Primary-key column. */
  key: string
  /** Bound columns in insert order; must include `updated_at`. `seq` is added automatically. */
  columns: readonly string[]
  values(row: T): unknown[]
}

/** D1 caps bound parameters per statement at 100. */
const MAX_PARAMS = 100
/** Keeps one statement's bound text well below D1's per-row / per-statement limits. */
const MAX_STATEMENT_TEXT = 900 * 1024

function textSize(values: unknown[]): number {
  return values.reduce<number>((sum, value) => sum + (typeof value === 'string' ? value.length : 8), 0)
}

function upsertSql(spec: RowTable<unknown>, rowCount: number, mode: WriteMode): string {
  const tuple = `(${spec.columns.map(() => '?').join(', ')}, ${SEQ})`
  const assignments = spec.columns
    .filter(column => column !== spec.key && column !== 'updated_at')
    .map(column => `${column} = excluded.${column}`)
  const updatedAt =
    mode === 'lww' ? 'updated_at = excluded.updated_at' : `updated_at = max(excluded.updated_at, ${spec.table}.updated_at + 1)`
  const where = mode === 'lww' ? ` WHERE excluded.updated_at > ${spec.table}.updated_at` : ''
  return (
    `INSERT INTO ${spec.table} (${spec.columns.join(', ')}, seq) VALUES ${Array(rowCount).fill(tuple).join(', ')} ` +
    `ON CONFLICT(${spec.key}) DO UPDATE SET ${[...assignments, updatedAt, 'seq = excluded.seq'].join(', ')}${where}`
  )
}

/** Multi-row upsert statements for `rows`, chunked to D1's statement limits. */
export function upsertStatements<T>(db: D1Database, spec: RowTable<T>, rows: readonly T[], mode: WriteMode): D1PreparedStatement[] {
  const rowsPerStatement = Math.max(1, Math.floor(MAX_PARAMS / spec.columns.length))
  const statements: D1PreparedStatement[] = []
  let chunk: unknown[][] = []
  let chunkText = 0
  const flush = () => {
    if (chunk.length === 0) return
    statements.push(db.prepare(upsertSql(spec as RowTable<unknown>, chunk.length, mode)).bind(...chunk.flat()))
    chunk = []
    chunkText = 0
  }
  for (const row of rows) {
    const values = spec.values(row)
    const size = textSize(values)
    if (chunk.length >= rowsPerStatement || (chunk.length > 0 && chunkText + size > MAX_STATEMENT_TEXT)) flush()
    chunk.push(values)
    chunkText += size
  }
  flush()
  return statements
}
