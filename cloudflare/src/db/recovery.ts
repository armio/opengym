/**
 * Daily recovery metrics from Apple Health (contract §8). The phone is the source of truth: every
 * upload replaces whole days, and a day with no metric left is deleted. No seq — these rows are
 * not synced to devices, only read by the MCP tools.
 */

export interface RecoveryDay {
  d: string
  /** Resting heart rate, bpm. */
  rhr: number | null
  /** Heart-rate variability (SDNN), ms. */
  hrv: number | null
  sleepMin: number | null
  inBedMin: number | null
}

interface RecoveryRow {
  d: string
  rhr: number | null
  hrv: number | null
  sleep_min: number | null
  in_bed_min: number | null
}

export const isEmptyRecoveryDay = (day: RecoveryDay): boolean =>
  day.rhr === null && day.hrv === null && day.sleepMin === null && day.inBedMin === null

/** Replaces the given days in one batch; returns how many were stored and deleted. */
export async function putRecoveryDays(db: D1Database, days: readonly RecoveryDay[], now: number): Promise<{ stored: number; deleted: number }> {
  if (days.length === 0) return { stored: 0, deleted: 0 }
  const statements = days.map(day =>
    isEmptyRecoveryDay(day)
      ? db.prepare('DELETE FROM recovery_daily WHERE d = ?').bind(day.d)
      : db
          .prepare(
            `INSERT INTO recovery_daily (d, rhr, hrv, sleep_min, in_bed_min, updated_at) VALUES (?, ?, ?, ?, ?, ?)
             ON CONFLICT (d) DO UPDATE SET rhr = excluded.rhr, hrv = excluded.hrv, sleep_min = excluded.sleep_min,
               in_bed_min = excluded.in_bed_min, updated_at = excluded.updated_at`,
          )
          .bind(day.d, day.rhr, day.hrv, day.sleepMin, day.inBedMin, now),
  )
  const results = await db.batch(statements)
  let stored = 0
  let deleted = 0
  days.forEach((day, i) => {
    if (isEmptyRecoveryDay(day)) deleted += results[i]!.meta.changes
    else stored++
  })
  return { stored, deleted }
}

/** Deletes every day; returns how many there were. */
export async function clearRecovery(db: D1Database): Promise<number> {
  const result = await db.prepare('DELETE FROM recovery_daily').run()
  return result.meta.changes
}

/** The statement `resetAllData` adds to its batch. */
export const clearRecoveryStatement = (db: D1Database): D1PreparedStatement => db.prepare('DELETE FROM recovery_daily')

/** Days in date order, optionally within inclusive 'YYYY-MM-DD' bounds. */
export async function listRecoveryDays(db: D1Database, range: { from?: string; to?: string } = {}): Promise<RecoveryDay[]> {
  const where: string[] = []
  const params: string[] = []
  if (range.from) {
    where.push('d >= ?')
    params.push(range.from)
  }
  if (range.to) {
    where.push('d <= ?')
    params.push(range.to)
  }
  const { results } = await db
    .prepare(`SELECT d, rhr, hrv, sleep_min, in_bed_min FROM recovery_daily${where.length ? ` WHERE ${where.join(' AND ')}` : ''} ORDER BY d`)
    .bind(...params)
    .all<RecoveryRow>()
  return results.map(row => ({ d: row.d, rhr: row.rhr, hrv: row.hrv, sleepMin: row.sleep_min, inBedMin: row.in_bed_min }))
}
