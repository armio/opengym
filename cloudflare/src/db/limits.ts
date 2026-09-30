/** Sliding-window rate limits for MCP writes, counted in `limits_log`. */
export interface RateLimit {
  kind: string
  max: number
  windowMs: number
}

/** Guard condition (for `guard()`): true when `limit` is already used up at `now`. */
export function limitExceededCondition(limit: RateLimit, now: number): [string, ...unknown[]] {
  return ['(SELECT count(*) FROM limits_log WHERE kind = ? AND at > ?) >= ?', limit.kind, now - limit.windowMs, limit.max]
}

export function recordLimitUse(db: D1Database, kind: string, now: number): D1PreparedStatement {
  return db.prepare('INSERT INTO limits_log (kind, at) VALUES (?, ?)').bind(kind, now)
}

export async function countLimitUses(db: D1Database, limit: RateLimit, now: number): Promise<number> {
  const row = await db
    .prepare('SELECT count(*) AS n FROM limits_log WHERE kind = ? AND at > ?')
    .bind(limit.kind, now - limit.windowMs)
    .first<{ n: number }>()
  return row?.n ?? 0
}

export async function pruneLimitsLog(db: D1Database, before: number): Promise<number> {
  const result = await db.prepare('DELETE FROM limits_log WHERE at < ?').bind(before).run()
  return result.meta.changes
}
