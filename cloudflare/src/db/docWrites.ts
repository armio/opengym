import { defaultDocData, docCasStatement, selectDocs, toDocState, type DocCasWrite, type DocRow, type DocState } from './docs'
import { guard, PreconditionFailedError, runGuardedBatch } from './guard'
import { limitExceededCondition, type RateLimit } from './limits'
import { expireProposalsStatement } from './proposals'
import { bumpSeq, SEQ } from './seq'

export type CasWriteResult =
  | { status: 'written'; doc: DocState }
  /** The doc moved past `baseSeq`; `doc` is the current version to retry from. */
  | { status: 'conflict'; doc: DocState }
  | { status: 'rate-limited' }

/**
 * A compare-and-swap doc write for MCP write tools (e.g. `update_athlete_profile`): one batch that
 * checks the optional rate limit, expires overdue proposals (contract §4.2), writes the doc if its
 * `seq` still equals `baseSeq`, and records the limit use only when the write applied.
 */
export async function casWriteDoc(db: D1Database, write: DocCasWrite, options: { now: number; limit?: RateLimit }): Promise<CasWriteResult> {
  const { now, limit } = options
  const statements = [
    ...(limit ? [guard(db, ...limitExceededCondition(limit, now))] : []),
    bumpSeq(db),
    expireProposalsStatement(db, now),
    docCasStatement(db, write),
  ]
  if (limit) {
    // The doc carries the counter value only if this batch wrote it.
    statements.push(
      db
        .prepare(`INSERT INTO limits_log (kind, at) SELECT ?, ? WHERE (SELECT seq FROM docs WHERE key = ?) = ${SEQ}`)
        .bind(limit.kind, now, write.key),
    )
  }
  statements.push(selectDocs(db, [write.key]))

  let results: D1Result[]
  try {
    results = await runGuardedBatch(db, statements)
  } catch (error) {
    if (error instanceof PreconditionFailedError) return { status: 'rate-limited' }
    throw error
  }
  const applied = results[limit ? 3 : 2]!.meta.changes > 0
  const row = results.at(-1)!.results[0] as DocRow | undefined
  const doc = row ? toDocState(row) : { key: write.key, data: defaultDocData(write.key), updatedAt: 0, seq: 0 }
  return applied ? { status: 'written', doc } : { status: 'conflict', doc }
}
