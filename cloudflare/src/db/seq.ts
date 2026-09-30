/**
 * The global change sequence (contract §3.1). A request that writes runs one `db.batch()` that
 * starts with `bumpSeq`, stamps every row it writes with `SEQ` and ends with `readCounters`.
 */

/** SQL expression for the current value of the change counter, used to stamp written rows. */
export const SEQ = "(SELECT value FROM counters WHERE name = 'seq')"

export function bumpSeq(db: D1Database): D1PreparedStatement {
  return db.prepare("UPDATE counters SET value = value + 1 WHERE name = 'seq'")
}

/**
 * Bumps the counter only if `condition` (an SQL boolean expression) holds, for writes whose
 * existence is only known inside the batch (e.g. expiring proposals on an otherwise empty push).
 */
export function bumpSeqIf(db: D1Database, condition: string, ...params: unknown[]): D1PreparedStatement {
  return db.prepare(`UPDATE counters SET value = value + 1 WHERE name = 'seq' AND (${condition})`).bind(...params)
}

export function readCounters(db: D1Database): D1PreparedStatement {
  return db.prepare("SELECT name, value FROM counters WHERE name IN ('seq', 'epoch')")
}

export interface Counters {
  seq: number
  epoch: number
}

export function parseCounters(result: D1Result): Counters {
  const rows = result.results as { name: string; value: number }[]
  const value = (name: string) => rows.find(row => row.name === name)?.value ?? 0
  return { seq: value('seq'), epoch: value('epoch') }
}

export async function getCounters(db: D1Database): Promise<Counters> {
  return parseCounters(await readCounters(db).all())
}
