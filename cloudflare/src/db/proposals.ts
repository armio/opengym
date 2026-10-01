import { newProposalId } from '../lib/ids'
import { parseJsonObject, type JsonObject } from '../lib/json'
import { DAY_MS } from '../lib/time'
import { docChangedCondition, docPutStatement, selectDocs, toDocState, type DocCasWrite, type DocKey, type DocRow, type DocState } from './docs'
import { guard, PreconditionFailedError, runGuardedBatch } from './guard'
import { limitExceededCondition, recordLimitUse, type RateLimit } from './limits'
import { bumpSeq, bumpSeqIf, SEQ } from './seq'

export const PROPOSAL_KINDS = ['plan', 'changes', 'nochange'] as const
export type ProposalKind = (typeof PROPOSAL_KINDS)[number]

export const PROPOSAL_STATUSES = ['pending', 'applied', 'dismissed', 'superseded', 'expired'] as const
export type ProposalStatus = (typeof PROPOSAL_STATUSES)[number]

export interface Resolution {
  outcome: 'applied' | 'dismissed'
  accepted: string[]
  rejected: string[]
  stale: string[]
  /** Plan proposals: whether the weekly schedule was replaced. */
  schedule?: boolean
}

/**
 * ProposalDTO (contract §4.5): the envelope plus the kind-specific body stored in `data`
 * (`bundle` for plan; `evidence`, `changes`, `notes` for changes; `reading` for nochange).
 */
export interface ProposalDTO {
  id: string
  kind: ProposalKind
  status: ProposalStatus
  createdAt: number
  expiresAt: number
  planHash: string | null
  unit: string
  iteration: number
  summary: string
  resolution: Resolution | null
  resolvedAt: number | null
  revertedAt: number | null
  seq: number
  [body: string]: unknown
}

/** Proposals stay pending for 14 days. */
export const PROPOSAL_TTL_MS = 14 * DAY_MS

/** `propose_*` and `report_no_change` together: at most 30 per 24 h (contract §5.2). */
export const PROPOSAL_RATE_LIMIT: RateLimit = { kind: 'propose', max: 30, windowMs: DAY_MS }

export class ProposalRateLimitError extends Error {
  constructor() {
    super(`Proposal limit reached: at most ${PROPOSAL_RATE_LIMIT.max} proposals per 24 hours.`)
  }
}

export interface ProposalRow {
  id: string
  kind: ProposalKind
  status: ProposalStatus
  created_at: number
  expires_at: number
  plan_hash: string | null
  unit: string
  iteration: number
  summary: string
  data: string
  resolution: string | null
  resolved_at: number | null
  reverted_at: number | null
  seq: number
}

export const PROPOSAL_COLUMNS =
  'id, kind, status, created_at, expires_at, plan_hash, unit, iteration, summary, data, resolution, resolved_at, reverted_at, seq'

export function toProposalDTO(row: ProposalRow): ProposalDTO {
  const envelope = {
    id: row.id,
    kind: row.kind,
    status: row.status,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    planHash: row.plan_hash,
    unit: row.unit,
    iteration: row.iteration,
    summary: row.summary,
    resolution: row.resolution ? (parseJsonObject(row.resolution) as unknown as Resolution) : null,
    resolvedAt: row.resolved_at,
    revertedAt: row.reverted_at,
    seq: row.seq,
  }
  return { ...parseJsonObject(row.data), ...envelope }
}

function selectProposal(db: D1Database, id: string): D1PreparedStatement {
  return db.prepare(`SELECT ${PROPOSAL_COLUMNS} FROM proposals WHERE id = ?`).bind(id)
}

export async function getProposal(db: D1Database, id: string): Promise<ProposalDTO | null> {
  const row = await selectProposal(db, id).first<ProposalRow>()
  return row ? toProposalDTO(row) : null
}

/** Proposals newest first, optionally filtered by status. */
export async function listProposals(db: D1Database, filter: { status?: ProposalStatus; limit?: number } = {}): Promise<ProposalDTO[]> {
  const where = filter.status ? 'WHERE status = ?' : ''
  const params: unknown[] = filter.status ? [filter.status] : []
  const limit = filter.limit !== undefined ? ' LIMIT ?' : ''
  if (filter.limit !== undefined) params.push(filter.limit)
  const { results } = await db
    .prepare(`SELECT ${PROPOSAL_COLUMNS} FROM proposals ${where} ORDER BY created_at DESC, id DESC${limit}`)
    .bind(...params)
    .all<ProposalRow>()
  return results.map(toProposalDTO)
}

const EXPIRABLE = "status = 'pending' AND expires_at < ?"

/** Flips pending proposals past `expiresAt` to `expired`; must run after a seq bump in the same batch. */
export function expireProposalsStatement(db: D1Database, now: number): D1PreparedStatement {
  return db.prepare(`UPDATE proposals SET status = 'expired', seq = ${SEQ} WHERE ${EXPIRABLE}`).bind(now)
}

/** Seq bump that happens only when some proposal is about to expire (for batches that may write nothing else). */
export function bumpSeqIfProposalsExpire(db: D1Database, now: number): D1PreparedStatement {
  return bumpSeqIf(db, `EXISTS (SELECT 1 FROM proposals WHERE ${EXPIRABLE})`, now)
}

/** Standalone expiry (cron): returns how many proposals expired. */
export async function expireProposals(db: D1Database, now: number): Promise<number> {
  const [, expired] = await db.batch([bumpSeqIfProposalsExpire(db, now), expireProposalsStatement(db, now)])
  return expired!.meta.changes
}

/** Marks every pending proposal `superseded` (import replace); must follow a seq bump. */
export function supersedePendingStatement(db: D1Database): D1PreparedStatement {
  return db.prepare(`UPDATE proposals SET status = 'superseded', seq = ${SEQ} WHERE status = 'pending'`)
}

/** Dismisses every pending proposal (reset); must follow a seq bump. */
export function dismissPendingStatement(db: D1Database, now: number): D1PreparedStatement {
  const resolution: Resolution = { outcome: 'dismissed', accepted: [], rejected: [], stale: [] }
  return db
    .prepare(`UPDATE proposals SET status = 'dismissed', resolution = ?, resolved_at = ?, seq = ${SEQ} WHERE status = 'pending'`)
    .bind(JSON.stringify(resolution), now)
}

export interface NewProposal {
  kind: ProposalKind
  summary: string
  /** Kind-specific body (contract §4.5), stored as the `data` column and spread into the DTO. */
  body: JsonObject
  planHash?: string | null
  iteration?: number
  /** Defaults to the stored `settings.unit` (else `kg`), read inside the same batch. */
  unit?: string
}

/**
 * Stores a proposal atomically with its side effects: expires overdue proposals, supersedes
 * pending proposals of the same kind (`nochange` supersedes nothing, coach-Q9) and records the
 * use against `PROPOSAL_RATE_LIMIT`. Throws `ProposalRateLimitError` when the limit is used up.
 */
export async function createProposal(db: D1Database, proposal: NewProposal, now = Date.now()): Promise<ProposalDTO> {
  const id = newProposalId()
  const statements = [
    guard(db, ...limitExceededCondition(PROPOSAL_RATE_LIMIT, now)),
    bumpSeq(db),
    expireProposalsStatement(db, now),
  ]
  if (proposal.kind !== 'nochange') {
    statements.push(
      db.prepare(`UPDATE proposals SET status = 'superseded', seq = ${SEQ} WHERE status = 'pending' AND kind = ?`).bind(proposal.kind),
    )
  }
  statements.push(
    db
      .prepare(
        `INSERT INTO proposals (id, kind, status, created_at, expires_at, plan_hash, unit, iteration, summary, data, seq)
         VALUES (?, ?, 'pending', ?, ?, ?,
                 coalesce(?, json_extract((SELECT data FROM docs WHERE key = 'settings'), '$.unit'), 'kg'),
                 ?, ?, ?, ${SEQ})`,
      )
      .bind(
        id,
        proposal.kind,
        now,
        now + PROPOSAL_TTL_MS,
        proposal.planHash ?? null,
        proposal.unit ?? null,
        proposal.iteration ?? 1,
        proposal.summary,
        JSON.stringify(proposal.body),
      ),
    recordLimitUse(db, PROPOSAL_RATE_LIMIT.kind, now),
    selectProposal(db, id),
  )
  let results: D1Result[]
  try {
    results = await runGuardedBatch(db, statements)
  } catch (error) {
    if (error instanceof PreconditionFailedError) throw new ProposalRateLimitError()
    throw error
  }
  return toProposalDTO(results.at(-1)!.results[0] as ProposalRow)
}

export interface ResolveInput {
  outcome: Resolution['outcome']
  accepted: string[]
  rejected: string[]
  stale: string[]
  schedule?: boolean
  docs: DocCasWrite[]
}

export interface RevertInput {
  docs: DocCasWrite[]
}

export type ResolveResult =
  | { status: 'ok'; proposal: ProposalDTO; docs: DocState[] }
  | { status: 'conflict'; reason: 'not-pending' | 'not-applied' | 'docs-changed'; proposal: ProposalDTO }
  | { status: 'not-found' }

function sameIds(a: readonly string[], b: readonly string[]): boolean {
  const left = new Set(a)
  const right = new Set(b)
  return left.size === right.size && [...left].every(id => right.has(id))
}

/** Same outcome and the same three id sets (the idempotent-retry test of contract §4.3). */
export function sameResolution(stored: Resolution | null, input: Omit<ResolveInput, 'docs'>): boolean {
  return (
    stored !== null &&
    stored.outcome === input.outcome &&
    sameIds(stored.accepted ?? [], input.accepted) &&
    sameIds(stored.rejected ?? [], input.rejected) &&
    sameIds(stored.stale ?? [], input.stale)
  )
}

async function currentDocs(db: D1Database, keys: readonly DocKey[]): Promise<DocState[]> {
  if (keys.length === 0) return []
  const { results } = await selectDocs(db, keys).all<DocRow>()
  return results.map(toDocState)
}

type Commit = { committed: true; proposal: ProposalDTO; docs: DocState[] } | { committed: false; proposal: ProposalDTO | null }

/** Runs a guarded proposal update together with its doc writes in one batch (contract §3.4). */
async function commitWithDocs(
  db: D1Database,
  id: string,
  statusGuard: [string, ...unknown[]],
  update: D1PreparedStatement,
  docs: readonly DocCasWrite[],
): Promise<Commit> {
  const statements = [
    guard(db, ...statusGuard),
    ...docs.map(doc => guard(db, ...docChangedCondition(doc.key, doc.baseSeq))),
    bumpSeq(db),
    update,
    ...docs.map(doc => docPutStatement(db, doc)),
    selectProposal(db, id),
    selectDocs(db, docs.map(doc => doc.key)),
  ]
  try {
    const results = await runGuardedBatch(db, statements)
    return {
      committed: true,
      proposal: toProposalDTO(results.at(-2)!.results[0] as ProposalRow),
      docs: (results.at(-1)!.results as DocRow[]).map(toDocState),
    }
  } catch (error) {
    if (!(error instanceof PreconditionFailedError)) throw error
    return { committed: false, proposal: await getProposal(db, id) }
  }
}

/**
 * Accepts or dismisses a pending proposal atomically with the app's doc writes (contract §4.3):
 * guards on the proposal being pending and on each doc's `seq` equal to its `baseSeq`. A retry
 * of a request that already took effect (same outcome and id sets) succeeds with the stored state.
 */
export async function resolveProposal(db: D1Database, id: string, input: ResolveInput, now = Date.now()): Promise<ResolveResult> {
  const keys = input.docs.map(doc => doc.key)
  const settle = async (proposal: ProposalDTO): Promise<ResolveResult> => {
    if (proposal.status === input.outcome && sameResolution(proposal.resolution, input)) {
      return { status: 'ok', proposal, docs: await currentDocs(db, keys) }
    }
    return { status: 'conflict', reason: proposal.status === 'pending' ? 'docs-changed' : 'not-pending', proposal }
  }
  const existing = await getProposal(db, id)
  if (!existing) return { status: 'not-found' }
  if (existing.status === 'pending' && existing.expiresAt < now) {
    // Overdue but not yet flipped (no sync or cron since): expire it now so the app and Claude
    // agree, and refuse the decision like any other non-pending proposal.
    await db.batch([bumpSeqIfProposalsExpire(db, now), expireProposalsStatement(db, now)])
    const expired = await getProposal(db, id)
    return expired ? settle(expired) : { status: 'not-found' }
  }
  if (existing.status !== 'pending') return settle(existing)

  const resolution: Resolution = {
    outcome: input.outcome,
    accepted: input.accepted,
    rejected: input.rejected,
    stale: input.stale,
    ...(input.schedule !== undefined && { schedule: input.schedule }),
  }
  const update = db
    .prepare(`UPDATE proposals SET status = ?, resolution = ?, resolved_at = ?, seq = ${SEQ} WHERE id = ?`)
    .bind(input.outcome, JSON.stringify(resolution), now, id)
  const pendingGuard: [string, ...unknown[]] = [
    "(SELECT status = 'pending' AND expires_at >= ? FROM proposals WHERE id = ?) IS NOT 1",
    now,
    id,
  ]
  const commit = await commitWithDocs(db, id, pendingGuard, update, input.docs)
  if (commit.committed) return { status: 'ok', proposal: commit.proposal, docs: commit.docs }
  return commit.proposal ? settle(commit.proposal) : { status: 'not-found' }
}

/**
 * Reverts an applied proposal atomically with the restored docs (contract §4.3): requires
 * `applied` and not yet reverted, guards each doc on its `baseSeq`, and sets `reverted_at`.
 * Reverting an already reverted proposal succeeds with the stored state.
 */
export async function revertProposal(db: D1Database, id: string, input: RevertInput, now = Date.now()): Promise<ResolveResult> {
  const keys = input.docs.map(doc => doc.key)
  const settle = async (proposal: ProposalDTO): Promise<ResolveResult> => {
    if (proposal.status === 'applied' && proposal.revertedAt !== null) {
      return { status: 'ok', proposal, docs: await currentDocs(db, keys) }
    }
    return { status: 'conflict', reason: proposal.status === 'applied' ? 'docs-changed' : 'not-applied', proposal }
  }
  const existing = await getProposal(db, id)
  if (!existing) return { status: 'not-found' }
  if (existing.status !== 'applied' || existing.revertedAt !== null) return settle(existing)

  const update = db.prepare(`UPDATE proposals SET reverted_at = ?, seq = ${SEQ} WHERE id = ?`).bind(now, id)
  const statusGuard: [string, ...unknown[]] = [
    "(SELECT status = 'applied' AND reverted_at IS NULL FROM proposals WHERE id = ?) IS NOT 1",
    id,
  ]
  const commit = await commitWithDocs(db, id, statusGuard, update, input.docs)
  if (commit.committed) return { status: 'ok', proposal: commit.proposal, docs: commit.docs }
  return commit.proposal ? settle(commit.proposal) : { status: 'not-found' }
}
