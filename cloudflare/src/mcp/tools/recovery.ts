import type { McpServer } from '@modelcontextprotocol/server'
import * as z from 'zod'
import { listRecoveryDays } from '../../db'
import { addDays } from '../../engine'
import { loadOwner } from '../owner'
import { buildRecovery, comparisonStart, RECOVERY_DEFAULT_DAYS, RECOVERY_MAX_DAYS } from '../payloads/recovery'
import { errorResult, jsonResult } from '../results'
import { isoDate } from '../schemas'
import { READ_ONLY } from './annotations'

/** `get_recovery` (contract §8): Apple Health recovery metrics the owner chose to share. */
export function registerRecoveryTools(server: McpServer, db: D1Database): void {
  server.registerTool(
    'get_recovery',
    {
      title: 'Recuperación (Apple Health)',
      description: `Recovery metrics the owner shares from Apple Health, one row per day (the owner's time zone; a night of sleep counts toward the morning it ends): rhr (resting heart rate, bpm), hrv (heart-rate variability SDNN, ms, daily mean), sleepMin (minutes asleep) and inBedMin. Any of them may be null — not every device records every metric.
- days: the rows between from and to (default: the last ${RECOVERY_DEFAULT_DAYS} days up to today).
- latest: the most recent day with data on or before to.
- comparison: the 7 days ending at to (recent, with shortNights under 6 h) against the 28 days before them (baseline): mean, sd and n per metric; comparable says whether there is enough data; signals describes clear differences (HRV below or above baseline by more than one sd, resting HR up, short or shorter sleep).
Recovery is context for structure — a deload week, fewer hard sets, moving a heavy day — never for day-to-day loads, which the progression engine sets. A few bad nights are normal; look for trends that persist and say what you see. These are not medical measurements: never diagnose. An empty days list means the owner has not shared recovery data for that range.`,
      inputSchema: z.object({
        from: isoDate.optional().describe('Earliest date, YYYY-MM-DD, inclusive.'),
        to: isoDate.optional().describe('Latest date, YYYY-MM-DD, inclusive (default today). The comparison ends here.'),
      }),
      annotations: READ_ONLY,
    },
    async ({ from, to }) => {
      const owner = await loadOwner(db)
      const end = to ?? owner.today
      const start = from ?? addDays(end, -(RECOVERY_DEFAULT_DAYS - 1))
      if (start > end) return errorResult(`from (${start}) is after to (${end}).`)
      if (start < addDays(end, -(RECOVERY_MAX_DAYS - 1))) return errorResult(`The range may span at most ${RECOVERY_MAX_DAYS} days.`)
      const load = start < comparisonStart(end) ? start : comparisonStart(end)
      return jsonResult(buildRecovery(await listRecoveryDays(db, { from: load, to: end }), start, end))
    },
  )
}
