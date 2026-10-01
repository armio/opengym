import type { ProposalDTO, ProposalStatus } from '../../db'
import type { Clock } from '../../engine'
import { isPlainObject, type JsonObject } from '../../lib/json'
import { localDate } from '../../lib/time'
import { localDateTimeOrNull } from './format'

/** How proposals and the owner's decisions on them appear in tool results. */

/**
 * A pending proposal past its expiry reads as expired. Read tools never write, so the stored
 * status only flips on the next write (contract §4.2); this keeps what Claude sees accurate.
 */
export function effectiveStatus(proposal: Pick<ProposalDTO, 'status' | 'expiresAt'>, now: number): ProposalStatus {
  return proposal.status === 'pending' && proposal.expiresAt < now ? 'expired' : proposal.status
}

interface ProposalChange {
  id: string
  type: string
  why?: string
}

function changesOf(proposal: ProposalDTO): ProposalChange[] {
  const changes = Array.isArray(proposal.changes) ? proposal.changes : []
  return changes.filter((c): c is ProposalChange => isPlainObject(c) && typeof c.id === 'string' && typeof c.type === 'string')
}

function bodySize(proposal: ProposalDTO): JsonObject {
  switch (proposal.kind) {
    case 'plan': {
      const bundle = isPlainObject(proposal.bundle) ? proposal.bundle : {}
      return { routines: Array.isArray(bundle.routines) ? bundle.routines.length : 0 }
    }
    case 'changes':
      return { changes: changesOf(proposal).length }
    case 'nochange':
      return {}
  }
}

function timestamps(proposal: ProposalDTO, clock: Clock) {
  return {
    createdAt: localDateTimeOrNull(proposal.createdAt, clock.tz),
    expiresAt: localDateTimeOrNull(proposal.expiresAt, clock.tz),
    resolvedAt: localDateTimeOrNull(proposal.resolvedAt, clock.tz),
    revertedAt: localDateTimeOrNull(proposal.revertedAt, clock.tz),
  }
}

/** A proposal without its body (`list_proposals`). */
export function proposalListItem(proposal: ProposalDTO, clock: Clock): JsonObject {
  return {
    id: proposal.id,
    kind: proposal.kind,
    status: effectiveStatus(proposal, clock.now),
    ...timestamps(proposal, clock),
    iteration: proposal.iteration,
    unit: proposal.unit,
    planHash: proposal.planHash,
    summary: proposal.summary,
    ...bodySize(proposal),
    resolution: proposal.resolution,
  }
}

/** The whole proposal (`get_proposal`), timestamps in the owner's zone. */
export function proposalDetail(proposal: ProposalDTO, clock: Clock): JsonObject {
  return { ...proposal, status: effectiveStatus(proposal, clock.now), ...timestamps(proposal, clock) }
}

const isDecided = (proposal: ProposalDTO) => (proposal.status === 'applied' || proposal.status === 'dismissed') && proposal.resolution !== null

/** Change ids → their types, in proposal order; a plan proposal's single decision is `plan`. */
function typesOf(proposal: ProposalDTO, ids: readonly string[]): string[] {
  if (proposal.kind === 'plan') return ids.includes('plan') ? ['plan'] : []
  const wanted = new Set(ids)
  return changesOf(proposal).filter(change => wanted.has(change.id)).map(change => change.type)
}

/** The last `limit` proposals the owner accepted or dismissed, newest first (`recentDecisions`). */
export function recentDecisions(proposals: readonly ProposalDTO[], clock: Clock, limit = 10): JsonObject[] {
  return proposals
    .filter(isDecided)
    .sort((a, b) => (b.resolvedAt ?? 0) - (a.resolvedAt ?? 0))
    .slice(0, limit)
    .map(proposal => {
      const resolution = proposal.resolution!
      return {
        id: proposal.id,
        kind: proposal.kind,
        outcome: resolution.outcome,
        resolvedAt: localDateTimeOrNull(proposal.resolvedAt, clock.tz),
        summary: proposal.summary,
        accepted: typesOf(proposal, resolution.accepted ?? []),
        rejected: typesOf(proposal, resolution.rejected ?? []),
        stale: typesOf(proposal, resolution.stale ?? []),
        ...(resolution.schedule !== undefined ? { schedule: resolution.schedule } : {}),
        reverted: proposal.revertedAt !== null,
      }
    })
}

interface Declined {
  type: string
  why: string
  at: number
}

/**
 * The last `limit` changes the owner turned down (`previouslyDeclined`), oldest first: the
 * rejected ids of resolved proposals plus the rejected decisions in the coach log (which also
 * holds history from before this server). A change recorded in both counts once.
 */
export function previouslyDeclined(proposals: readonly ProposalDTO[], coach: JsonObject, clock: Clock, limit = 15): { type: string; why: string; d: string | null }[] {
  const declined = new Map<string, Declined>()
  for (const proposal of proposals.filter(isDecided)) {
    const rejected = new Set(proposal.resolution!.rejected ?? [])
    for (const change of changesOf(proposal)) {
      if (rejected.has(change.id)) declined.set(`${proposal.id}:${change.id}`, { type: change.type, why: change.why ?? '', at: proposal.resolvedAt ?? 0 })
    }
  }
  const log = Array.isArray(coach.log) ? coach.log.filter(isPlainObject) : []
  for (const entry of log) {
    const decisions = Array.isArray(entry.decisions) ? entry.decisions.filter(isPlainObject) : []
    for (const decision of decisions) {
      if (decision.status !== 'rejected' || typeof decision.type !== 'string') continue
      const key = `${String(entry.proposalId ?? '')}:${String(decision.id ?? '')}`
      if (!declined.has(key)) {
        declined.set(key, { type: decision.type, why: typeof decision.why === 'string' ? decision.why : '', at: typeof entry.at === 'number' ? entry.at : 0 })
      }
    }
  }
  return [...declined.values()]
    .sort((a, b) => a.at - b.at)
    .slice(-limit)
    .map(item => ({ type: item.type, why: item.why, d: item.at > 0 ? localDate(item.at, clock.tz) : null }))
}
