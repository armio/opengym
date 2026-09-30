import { DAY_MS, HOUR_MS, MINUTE_MS } from '../lib/time'

/** Login and consent attempts per client key in 15 minutes, and across all keys in an hour. */
export const AUTH_LIMITS = { perKey: 10, perKeyWindowMs: 15 * MINUTE_MS, global: 200, globalWindowMs: HOUR_MS }

export interface AuthAttempt {
  /** Row id of the recorded attempt, deleted again when the password turns out right. */
  id: number
  limited: boolean
}

/**
 * Records an attempt before the password is checked and tells whether the caller is over the
 * limit (contract §4.1): more than 10 attempts for `key` in 15 minutes or 200 overall in an hour.
 */
export async function recordAuthAttempt(db: D1Database, key: string, now: number): Promise<AuthAttempt> {
  const [inserted, perKey, global] = await db.batch([
    db.prepare('INSERT INTO auth_failures (ip, at) VALUES (?, ?) RETURNING rowid AS id').bind(key, now),
    db.prepare('SELECT count(*) AS n FROM auth_failures WHERE ip = ? AND at > ?').bind(key, now - AUTH_LIMITS.perKeyWindowMs),
    db.prepare('SELECT count(*) AS n FROM auth_failures WHERE at > ?').bind(now - AUTH_LIMITS.globalWindowMs),
  ])
  const count = (result: D1Result | undefined) => (result?.results[0] as { n: number } | undefined)?.n ?? 0
  return {
    id: (inserted!.results[0] as { id: number }).id,
    limited: count(perKey) > AUTH_LIMITS.perKey || count(global) > AUTH_LIMITS.global,
  }
}

/** Forgets a successful attempt so it does not count against the owner. */
export async function clearAuthAttempt(db: D1Database, id: number): Promise<void> {
  await db.prepare('DELETE FROM auth_failures WHERE rowid = ?').bind(id).run()
}

export async function pruneAuthFailures(db: D1Database, before: number): Promise<number> {
  const result = await db.prepare('DELETE FROM auth_failures WHERE at < ?').bind(before).run()
  return result.meta.changes
}

export const AUTH_FAILURE_RETENTION_MS = DAY_MS
