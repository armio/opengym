import type { BodyweightItem } from './bodyweight'
import { upsertBodyweight } from './bodyweight'
import { docCasStatement, type DocCasWrite, type DocKey } from './docs'
import { upsertExWeights, type ExWeightItem } from './exWeights'
import { bumpSeqIfProposalsExpire, expireProposalsStatement } from './proposals'
import { parsePull, pullStatements, type PullResult } from './pull'
import { bumpSeq } from './seq'
import { upsertWorkouts, type WorkoutItem } from './workouts'

export interface SyncPush {
  since: number
  docs: DocCasWrite[]
  workouts: WorkoutItem[]
  bodyweight: BodyweightItem[]
  exWeights: ExWeightItem[]
}

export interface SyncOutcome extends PullResult {
  /** Pushed docs whose compare-and-swap did not apply. */
  conflicts: DocKey[]
}

/** `GET /api/sync`: one read-only batch, so the rows and the counter are consistent. */
export async function pullChanges(db: D1Database, since: number): Promise<PullResult> {
  return parsePull(await db.batch(pullStatements(db, since)))
}

/**
 * `POST /api/sync` (contract §3.1–§3.2) as one batch: bump the counter, expire overdue proposals,
 * compare-and-swap the docs, last-writer-wins the rows, then read the page and the counters.
 */
export async function pushAndPull(db: D1Database, push: SyncPush, now: number): Promise<SyncOutcome> {
  const writesRows = push.docs.length + push.workouts.length + push.bodyweight.length + push.exWeights.length > 0
  const docStatements = push.docs.map(doc => docCasStatement(db, doc))
  const statements = [
    writesRows ? bumpSeq(db) : bumpSeqIfProposalsExpire(db, now),
    expireProposalsStatement(db, now),
    ...docStatements,
    ...upsertWorkouts(db, push.workouts, 'lww'),
    ...upsertBodyweight(db, push.bodyweight, 'lww'),
    ...upsertExWeights(db, push.exWeights, 'lww'),
    ...pullStatements(db, push.since, {
      docs: push.docs.map(doc => doc.key),
      workouts: push.workouts.map(w => w.id),
      bodyweight: push.bodyweight.map(b => b.d),
      exWeights: push.exWeights.map(x => x.id),
    }),
  ]
  const results = await db.batch(statements)
  const docResults = results.slice(2, 2 + docStatements.length)
  const conflicts = push.docs.filter((_, i) => docResults[i]!.meta.changes === 0).map(doc => doc.key)
  return { ...parsePull(results), conflicts }
}
