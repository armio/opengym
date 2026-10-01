import { BODYWEIGHT_COLUMNS, toBodyweightRecord, type BodyweightRecord, type BodyweightRow } from './bodyweight'
import { DOC_COLUMNS, toDocState, type DocRow, type DocState } from './docs'
import { EX_WEIGHT_COLUMNS, toExWeightRecord, type ExWeightRecord, type ExWeightRow } from './exWeights'
import { PROPOSAL_COLUMNS, toProposalDTO, type ProposalDTO, type ProposalRow } from './proposals'
import { parseCounters, readCounters } from './seq'
import { toWorkoutRecord, WORKOUT_COLUMNS, type WorkoutRecord, type WorkoutRow } from './workouts'

/** Rows returned per pull, across tables (contract §3.2). */
export const PULL_ROW_LIMIT = 500

/** Keys of pushed items whose current server version is always echoed back. */
export interface PushedKeys {
  docs: string[]
  workouts: string[]
  bodyweight: string[]
  exWeights: string[]
}

export const NO_PUSHED_KEYS: PushedKeys = { docs: [], workouts: [], bodyweight: [], exWeights: [] }

export interface PullResult {
  seq: number
  epoch: number
  hasMore: boolean
  docs: DocState[]
  workouts: WorkoutRecord[]
  bodyweight: BodyweightRecord[]
  exWeights: ExWeightRecord[]
  proposals: ProposalDTO[]
}

/**
 * Change groups after `since` (?1): every changed row is counted once per seq. The cutoff is the
 * highest seq whose running total stays within the row limit, so a page never splits the rows of
 * one seq (clients resume from an integer seq). A single group larger than the limit is returned
 * whole rather than skipped.
 */
const CHANGE_GROUPS = `
  changes(seq) AS (
    SELECT seq FROM docs WHERE seq > ?1
    UNION ALL SELECT seq FROM workouts WHERE seq > ?1
    UNION ALL SELECT seq FROM bodyweight WHERE seq > ?1
    UNION ALL SELECT seq FROM ex_weights WHERE seq > ?1
    UNION ALL SELECT seq FROM proposals WHERE seq > ?1),
  groups(seq, n) AS (SELECT seq, count(*) FROM changes GROUP BY seq),
  running(seq, total) AS (SELECT seq, sum(n) OVER (ORDER BY seq) FROM groups)`

const CUTOFF = `coalesce((SELECT max(seq) FROM running WHERE total <= ${PULL_ROW_LIMIT}), (SELECT min(seq) FROM groups))`

const IN_RANGE = `(seq > ?1 AND seq <= (WITH ${CHANGE_GROUPS} SELECT ${CUTOFF}))`

/**
 * The read half of a sync request, to append to its batch after any writes: one statement for
 * the page bounds, one per table (rows in range plus the echoed pushed keys) and the counters.
 * Parse the results with `parsePull`.
 */
export function pullStatements(db: D1Database, since: number, pushed: PushedKeys = NO_PUSHED_KEYS): D1PreparedStatement[] {
  const echo = (column: string) => `${column} IN (SELECT value FROM json_each(?2))`
  const table = (columns: string, name: string, key: string, keys: string[]) =>
    db
      .prepare(`SELECT ${columns} FROM ${name} WHERE ${IN_RANGE} OR ${echo(key)} ORDER BY seq`)
      .bind(since, JSON.stringify(keys))
  return [
    db.prepare(`WITH ${CHANGE_GROUPS} SELECT ${CUTOFF} AS cutoff, (SELECT max(seq) FROM groups) AS last`).bind(since),
    table(DOC_COLUMNS, 'docs', 'key', pushed.docs),
    table(WORKOUT_COLUMNS, 'workouts', 'id', pushed.workouts),
    table(BODYWEIGHT_COLUMNS, 'bodyweight', 'd', pushed.bodyweight),
    table(EX_WEIGHT_COLUMNS, 'ex_weights', 'ex_id', pushed.exWeights),
    db.prepare(`SELECT ${PROPOSAL_COLUMNS} FROM proposals WHERE ${IN_RANGE} ORDER BY seq`).bind(since),
    readCounters(db),
  ]
}

export const PULL_STATEMENT_COUNT = 7

/** Parses the last `PULL_STATEMENT_COUNT` results of a batch built with `pullStatements`. */
export function parsePull(results: readonly D1Result[]): PullResult {
  const [bounds, docs, workouts, bodyweight, exWeights, proposals, counters] = results.slice(-PULL_STATEMENT_COUNT) as D1Result[]
  const { cutoff, last } = bounds!.results[0] as { cutoff: number | null; last: number | null }
  const { seq, epoch } = parseCounters(counters!)
  const hasMore = cutoff !== null && last !== null && cutoff < last
  return {
    seq: hasMore ? cutoff : seq,
    epoch,
    hasMore,
    docs: (docs!.results as DocRow[]).map(toDocState),
    workouts: (workouts!.results as WorkoutRow[]).map(toWorkoutRecord),
    bodyweight: (bodyweight!.results as BodyweightRow[]).map(toBodyweightRecord),
    exWeights: (exWeights!.results as ExWeightRow[]).map(toExWeightRecord),
    proposals: (proposals!.results as ProposalRow[]).map(toProposalDTO),
  }
}
