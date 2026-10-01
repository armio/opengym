import type { OAuthProvider } from '@cloudflare/workers-oauth-provider'
import { AUTH_FAILURE_RETENTION_MS, pruneAuthFailures } from './db/authFailures'
import { pruneLimitsLog } from './db/limits'
import { expireProposals } from './db/proposals'
import { DAY_MS } from './lib/time'

/** Where the resumable OAuth KV sweep keeps its position between runs. */
export const PURGE_CURSOR_KEY = 'opengym:purge-cursor'
const PURGE_BATCH_SIZE = 100

async function purgeOAuthData(provider: OAuthProvider<Env>, env: Env): Promise<void> {
  const cursor = (await env.OAUTH_KV.get(PURGE_CURSOR_KEY)) ?? undefined
  const result = await provider.purgeExpiredData(env, { batchSize: PURGE_BATCH_SIZE, ...(cursor && { cursor }) })
  if (result.cursor) await env.OAUTH_KV.put(PURGE_CURSOR_KEY, result.cursor)
  else await env.OAUTH_KV.delete(PURGE_CURSOR_KEY)
}

/**
 * The daily cron (contract §5): purge expired OAuth data, prune auth failures and rate-limit logs
 * older than a day, expire overdue proposals. Every task runs even if another fails.
 */
export async function runDailyCleanup(provider: OAuthProvider<Env>, env: Env, now = Date.now()): Promise<void> {
  const tasks = await Promise.allSettled([
    purgeOAuthData(provider, env),
    pruneAuthFailures(env.DB, now - AUTH_FAILURE_RETENTION_MS),
    pruneLimitsLog(env.DB, now - DAY_MS),
    expireProposals(env.DB, now),
  ])
  const failures = tasks.filter((task): task is PromiseRejectedResult => task.status === 'rejected')
  if (failures.length > 0) {
    throw new AggregateError(failures.map(failure => failure.reason), 'daily cleanup failed')
  }
}
