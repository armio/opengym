import type { McpServer } from '@modelcontextprotocol/server'
import * as z from 'zod'
import { foldText, LIBRARY } from '../../catalog/library'
import { casWriteDoc, getDoc, ownerTimeZone, type RateLimit } from '../../db'
import type { JsonObject } from '../../lib/json'
import { DAY_MS } from '../../lib/time'
import { errorResult, jsonResult } from '../results'
import { EQUIPMENT_LABELS } from '../schemas'
import { ATHLETE_FIELDS, athleteView, EXPERIENCE, GOALS } from '../views/athlete'
import { OVERWRITES_PROFILE } from './annotations'

/**
 * `update_athlete_profile` (contract §5.2): the one doc Claude writes directly. A validated merge
 * into the `athlete` doc with compare-and-swap on its version, stamped `updatedBy: 'claude'`.
 */

export const ATHLETE_RATE_LIMIT: RateLimit = { kind: 'athlete', max: 10, windowMs: DAY_MS }

/** Compare-and-swap attempts before giving up on a doc that keeps changing underneath. */
const CAS_ATTEMPTS = 3

const inputSchema = z.object({
  goal: z.enum(GOALS).nullable().optional().describe('strength, muscle, general (general fitness), fatloss or endurance; null to clear.'),
  experience: z.enum(EXPERIENCE).nullable().optional().describe('new (new to lifting), returning (after a break) or regular (training regularly); null to clear.'),
  daysPerWeek: z.number().int().min(1).max(7).optional().describe('Training days per week, 1–7. Plans must schedule exactly this many.'),
  preferredDays: z.array(z.number().int().min(0).max(6)).max(7).optional().describe('Weekdays that suit them: 0 = Sunday, 1 = Monday … 6 = Saturday. [] = no preference.'),
  sessionMin: z.number().int().min(15).max(180).optional().describe('Minutes per session, 15–180.'),
  equipment: z.array(z.string().max(40)).max(28).optional().describe(`Equipment they have, English or Spanish library values: ${EQUIPMENT_LABELS}. [] = everything.`),
  limitations: z.string().max(600).optional().describe('Injuries or limitations in their words (≤ 600 characters). Record pain as described; never diagnose.'),
  likes: z.string().max(300).optional().describe('Exercises or styles they enjoy (≤ 300).'),
  dislikes: z.string().max(300).optional().describe('Exercises they would rather avoid (≤ 300).'),
  notes: z.string().max(600).optional().describe('Anything else they want the coach to know (≤ 600).'),
})

type ProfileInput = z.infer<typeof inputSchema>

const EQUIPMENT: ReadonlyMap<string, string> = new Map(LIBRARY.flatMap(record => [[foldText(record.eq), record.eq], [foldText(record.eq_es), record.eq]]))

/** The fields to write, normalised; errors for equipment the library does not know. */
function profileChanges(input: ProfileInput): { changes: JsonObject; errors: string[] } {
  const changes: JsonObject = {}
  const errors: string[] = []
  for (const field of ATHLETE_FIELDS) {
    const value = input[field]
    if (value === undefined) continue
    if (field === 'preferredDays') changes[field] = [...new Set(value as number[])].sort((a, b) => a - b)
    else if (field === 'equipment') {
      const known = (value as string[]).map(item => ({ item, eq: EQUIPMENT.get(foldText(item)) }))
      for (const { item } of known.filter(k => !k.eq)) errors.push(`equipment "${item}" is not a library equipment value`)
      changes[field] = [...new Set(known.flatMap(k => (k.eq ? [k.eq] : [])))]
    } else changes[field] = typeof value === 'string' ? value.trim() : value
  }
  return { changes, errors }
}

export function registerAthleteTools(server: McpServer, db: D1Database): void {
  server.registerTool(
    'update_athlete_profile',
    {
      title: 'Actualizar perfil del atleta',
      description: `Saves the owner's Coach profile: goal, experience, availability (daysPerWeek, preferredDays, sessionMin), equipment and, in their own words, limitations, likes, dislikes and notes. Only the fields you pass change; the others keep their values. Write only what the owner told you or agreed to. The app shows them that Claude updated the profile. At most ${ATHLETE_RATE_LIMIT.max} updates per 24 hours. Returns the saved profile.`,
      inputSchema,
      annotations: OVERWRITES_PROFILE,
    },
    async input => {
      const { changes, errors } = profileChanges(input)
      if (errors.length) return errorResult('The profile was not saved. Fix every problem below and call update_athlete_profile again.', errors)
      if (!Object.keys(changes).length) return errorResult('Nothing to update: pass at least one profile field.')

      let doc = await getDoc(db, 'athlete')
      for (let attempt = 0; attempt < CAS_ATTEMPTS; attempt++) {
        const now = Date.now()
        const data = { ...doc.data, ...changes, savedAt: now, updatedBy: 'claude' }
        const result = await casWriteDoc(db, { key: 'athlete', data, baseSeq: doc.seq, updatedAt: now }, { now, limit: ATHLETE_RATE_LIMIT })
        if (result.status === 'written') {
          return jsonResult({ athlete: athleteView(result.doc.data, await ownerTimeZone(db)), changed: Object.keys(changes) })
        }
        if (result.status === 'rate-limited') {
          return errorResult(`The profile was not saved: at most ${ATHLETE_RATE_LIMIT.max} profile updates per 24 hours. Tell the owner they can edit it in the app's Coach tab.`)
        }
        doc = result.doc
      }
      return errorResult('The profile was not saved because it kept changing in the app. Read it again with get_overview and retry.')
    },
  )
}
