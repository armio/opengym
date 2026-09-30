import type { DocKey } from '../db/docs'
import type { PullResult } from '../db/pull'
import { pullChanges, pushAndPull } from '../db/sync'
import { jsonResponse, MIB, readJsonBody } from '../lib/http'
import type { DeviceContext } from './context'
import { parseSince, parseSyncPush, type Rejected } from './syncInput'

function syncResponse(result: PullResult, conflicts: readonly DocKey[] = [], rejected: readonly Rejected[] = []): Response {
  return jsonResponse({
    seq: result.seq,
    epoch: result.epoch,
    serverTime: Date.now(),
    hasMore: result.hasMore,
    docs: result.docs,
    workouts: result.workouts,
    bodyweight: result.bodyweight,
    exWeights: result.exWeights,
    proposals: result.proposals,
    conflicts: conflicts.map(key => ({ kind: 'doc', key })),
    rejected,
  })
}

/** `GET /api/sync?since=N`: read-only pull (contract §3.2). */
export async function pull({ env, url }: DeviceContext): Promise<Response> {
  return syncResponse(await pullChanges(env.DB, parseSince(url.searchParams.get('since'))))
}

/** `POST /api/sync`: push (docs by compare-and-swap, rows by LWW) and pull in one batch. */
export async function pushPull({ request, env, now }: DeviceContext): Promise<Response> {
  const { push, rejected } = parseSyncPush(await readJsonBody(request, MIB), now)
  const outcome = await pushAndPull(env.DB, push, now)
  return syncResponse(outcome, outcome.conflicts, rejected)
}
