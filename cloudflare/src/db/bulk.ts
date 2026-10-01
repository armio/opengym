import { upsertBodyweight, type BodyweightItem } from './bodyweight'
import { defaultDocData, DOC_KEYS, docPutStatement, type DocWrite } from './docs'
import { upsertExWeights, type ExWeightItem } from './exWeights'
import { dismissPendingStatement, supersedePendingStatement } from './proposals'
import { bumpSeq, parseCounters, readCounters, SEQ } from './seq'
import { upsertWorkouts, type WorkoutItem } from './workouts'

/** Statements per import batch; each batch is its own transaction (contract §4.4). */
const IMPORT_BATCH_SIZE = 200

const ROW_TABLES = {
  workouts: { key: 'id', clear: 'data = NULL' },
  bodyweight: { key: 'd', clear: 'w = NULL, t = NULL' },
  ex_weights: { key: 'ex_id', clear: 'w = NULL, d = NULL' },
} as const

type RowTableName = keyof typeof ROW_TABLES

/** Tombstones every live row of `table`, except the keys in `keep`. Must follow a seq bump. */
function tombstoneStatement(db: D1Database, table: RowTableName, now: number, keep: readonly string[] = []): D1PreparedStatement {
  const { key, clear } = ROW_TABLES[table]
  return db
    .prepare(
      `UPDATE ${table} SET deleted = 1, ${clear}, updated_at = max(?1, updated_at + 1), seq = ${SEQ}
       WHERE deleted = 0 AND ${key} NOT IN (SELECT value FROM json_each(?2))`,
    )
    .bind(now, JSON.stringify(keep))
}

export interface ImportData {
  docs: DocWrite[]
  workouts: WorkoutItem[]
  bodyweight: BodyweightItem[]
  exWeights: ExWeightItem[]
  /** Ids/dates a replace import must not tombstone; defaults to the imported rows. */
  keep?: { workouts: string[]; bodyweight: string[]; exWeights: string[] }
}

/**
 * Writes an imported backup (contract §4.4). Rows go first, in batches that each bump the seq;
 * the last batch tombstones what the file lacks (replace), supersedes pending proposals (replace)
 * and writes the docs. Every step overwrites, so a failed import can simply be retried.
 */
export async function writeImport(db: D1Database, data: ImportData, mode: 'replace' | 'merge', now: number): Promise<void> {
  const rowStatements = [
    ...upsertWorkouts(db, data.workouts, 'force'),
    ...upsertBodyweight(db, data.bodyweight, 'force'),
    ...upsertExWeights(db, data.exWeights, 'force'),
  ]
  for (let i = 0; i < rowStatements.length; i += IMPORT_BATCH_SIZE - 1) {
    await db.batch([bumpSeq(db), ...rowStatements.slice(i, i + IMPORT_BATCH_SIZE - 1)])
  }
  const final = [bumpSeq(db)]
  if (mode === 'replace') {
    final.push(
      tombstoneStatement(db, 'workouts', now, data.keep?.workouts ?? data.workouts.map(w => w.id)),
      tombstoneStatement(db, 'bodyweight', now, data.keep?.bodyweight ?? data.bodyweight.map(b => b.d)),
      tombstoneStatement(db, 'ex_weights', now, data.keep?.exWeights ?? data.exWeights.map(x => x.id)),
      supersedePendingStatement(db),
    )
  }
  final.push(...data.docs.map(doc => docPutStatement(db, doc)))
  await db.batch(final)
}

/**
 * "Borrar todo" (contract §4.6): tombstones every workout, body-weight and working-weight row,
 * writes default docs and dismisses pending proposals, in one batch. Returns the new seq.
 */
export async function resetAllData(db: D1Database, now: number): Promise<number> {
  const results = await db.batch([
    bumpSeq(db),
    tombstoneStatement(db, 'workouts', now),
    tombstoneStatement(db, 'bodyweight', now),
    tombstoneStatement(db, 'ex_weights', now),
    dismissPendingStatement(db, now),
    ...DOC_KEYS.map(key => docPutStatement(db, { key, data: defaultDocData(key), updatedAt: now })),
    readCounters(db),
  ])
  return parseCounters(results.at(-1)!).seq
}
