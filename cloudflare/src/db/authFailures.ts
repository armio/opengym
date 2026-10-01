import { DAY_MS, HOUR_MS, MINUTE_MS } from '../lib/time'

/**
 * Login and consent attempts per client key in 15 minutes, and across all keys in an hour. The
 * global cap only guards the D1 write quota: attempts over a key's own limit are not recorded,
 * so one client cannot fill it and lock the owner out everywhere.
 */
export const AUTH_LIMITS = { perKey: 10, perKeyWindowMs: 15 * MINUTE_MS, global: 500, globalWindowMs: HOUR_MS }

export interface AuthAttempt {
  /** Row id of the recorded attempt, deleted again when the password turns out right; null when limited. */
  id: number | null
  limited: boolean
}

/**
 * Records an attempt before the password is checked and tells whether the caller is over the
 * limit (contract §4.1). The row is inserted only while `key` is under its limit, in the same
 * batch as the global count, so concurrent attempts cannot race past either.
 */
export async function recordAuthAttempt(db: D1Database, key: string, now: number): Promise<AuthAttempt> {
  const [inserted, global] = await db.batch([
    db
      .prepare(
        `INSERT INTO auth_failures (ip, at)
         SELECT ?1, ?2 WHERE (SELECT count(*) FROM auth_failures WHERE ip = ?1 AND at > ?3) < ?4
         RETURNING rowid AS id`,
      )
      .bind(key, now, now - AUTH_LIMITS.perKeyWindowMs, AUTH_LIMITS.perKey),
    db.prepare('SELECT count(*) AS n FROM auth_failures WHERE at > ?').bind(now - AUTH_LIMITS.globalWindowMs),
  ])
  const id = (inserted?.results[0] as { id: number } | undefined)?.id ?? null
  const globalCount = (global?.results[0] as { n: number } | undefined)?.n ?? 0
  if (id === null) return { id: null, limited: true }
  return { id, limited: globalCount > AUTH_LIMITS.global }
}

/** Forgets a successful attempt so it does not count against the owner. */
export async function clearAuthAttempt(db: D1Database, id: number | null): Promise<void> {
  if (id === null) return
  await db.prepare('DELETE FROM auth_failures WHERE rowid = ?').bind(id).run()
}

export async function pruneAuthFailures(db: D1Database, before: number): Promise<number> {
  const result = await db.prepare('DELETE FROM auth_failures WHERE at < ?').bind(before).run()
  return result.meta.changes
}

export const AUTH_FAILURE_RETENTION_MS = DAY_MS
