import * as z from 'zod'
import { LIBRARY } from '../catalog/library'
import { isIsoDate } from '../lib/time'

/**
 * Zod building blocks shared by the tool input schemas. Descriptions are what Claude reads in
 * `tools/list`, so they carry the domain rules; the coach validators remain the security boundary.
 */

export const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'must be a date written YYYY-MM-DD')
  .refine(isIsoDate, 'must be a real calendar date')

export const REPS_POLICIES = ['off', 'linear', 'greyskull', 'double'] as const
export const POLICY_VALUES = ['off', 'linear', 'greyskull', 'double', 'time'] as const
export const MODE_VALUES = ['reps', 'time', 'cardio'] as const

/** The library's body parts in English, as stored in custom exercises. */
export const BODY_PARTS = [...new Set(LIBRARY.map(record => record.bp))].sort() as [string, ...string[]]

/** English library value → Spanish label, for descriptions. */
function labelPairs(pick: (record: (typeof LIBRARY)[number]) => [string, string]): string {
  const pairs = new Map(LIBRARY.map(pick))
  return [...pairs].map(([en, es]) => (en === es ? en : `${en}/${es}`)).join(', ')
}

export const BODY_PART_LABELS = labelPairs(record => [record.bp, record.bp_es])
export const EQUIPMENT_LABELS = labelPairs(record => [record.eq, record.eq_es])

export const exerciseId = z.string().trim().min(1).max(64)

export const proposalId = z.string().trim().regex(/^p[0-9a-f]{16}$/, 'must be a proposal id such as "p1a2b3c4d5e6f7a8b"')
