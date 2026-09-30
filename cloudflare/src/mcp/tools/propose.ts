import type { CallToolResult, McpServer } from '@modelcontextprotocol/server'
import * as z from 'zod'
import { CHANGE_TYPES, validateChangesProposal, validatePlanProposal, type PortContext } from '../../coach'
import { createProposal, getProposal, ProposalRateLimitError, PROPOSAL_RATE_LIMIT, type NewProposal, type ProposalDTO } from '../../db'
import { heaviestDoneSets } from '../../engine'
import { loadOwner, loadTraining, type Owner, type Training } from '../owner'
import { CHANGE_TYPE_GUIDE } from '../changeTypes'
import { errorResult, jsonResult } from '../results'
import { BODY_PARTS, isoDate, MODE_VALUES, POLICY_VALUES, proposalId, REPS_POLICIES } from '../schemas'
import { MONDAY_FIRST, WEEKDAY_NAMES } from '../views/format'
import { currentPlanHash } from '../views/plan'
import { PROPOSES } from './annotations'

/**
 * `propose_plan`, `propose_changes` and `report_no_change` (contract §5.2–§5.3). The zod schemas
 * describe the shapes; the coach validators decide what may be stored. Nothing here touches the
 * plan: proposals wait for the owner in the app.
 */

const INERT = "Stored as a pending proposal. Nothing has changed yet: the owner accepts or discards it in the app's Coach tab."

/* ------------------------------------------------------------------ schemas */

const planExercise = z.object({
  id: z.string().min(1).describe('Exercise id from search_exercises or get_overview (library or the owner\'s custom exercises), or a customEx id defined in this plan.'),
  sets: z.number().int().min(1).max(10).describe('Working sets, 1–10.'),
  mode: z.enum(MODE_VALUES).optional().describe('reps (set reps), time (set sec) or cardio (set min and speed). cardio exactly for cardio exercises. Omitted: cardio for cardio exercises, else reps.'),
  reps: z.number().int().min(1).max(100).optional().describe('reps mode: target reps per set (the top of the range under double progression). Default 10.'),
  sec: z.number().int().min(5).max(3600).optional().describe('time mode: seconds per set. Default 45.'),
  min: z.number().int().min(1).max(180).optional().describe('cardio mode: minutes. Default 20.'),
  speed: z.number().positive().optional().describe('cardio mode: km/h. Default 8.'),
  weight: z.number().min(0).optional().describe('Starting load in meta.unit, only for an exercise they have not trained yet; capped at workingWeights.best. Omit it otherwise: the first session sets the baseline.'),
  prog: z.enum(POLICY_VALUES).optional().describe('Progression policy for this exercise, overriding the routine\'s. reps: off|linear|greyskull|double; time: off|time; cardio: off.'),
  inc: z.number().positive().optional().describe('Progression step in meta.unit (seconds for time mode). Omit for the default: 2.5 kg / 5 lb, 5 kg / 10 lb for legs and back; 5 s.'),
  repsMin: z.number().int().min(1).max(100).optional().describe('Bottom of the rep range; only double progression uses it (default reps − 2).'),
  sg: z.string().max(20).optional().describe('Superset tag: give two adjacent exercises the same short string, e.g. "a".'),
  why: z.string().max(400).optional().describe('1–2 sentences in Spanish: why this exercise, here, at this prescription.'),
})

const planRoutine = z.object({
  id: z.string().min(1).max(40).describe('Your id for the routine inside this plan, e.g. "r1"; week refers to it. The app assigns real ids on accept.'),
  name: z.string().min(1).max(40).describe('Routine name in Spanish, e.g. "Empuje", "Pierna A".'),
  emoji: z.string().max(40).optional().describe('One emoji (at most 8 characters are kept).'),
  prog: z.enum(REPS_POLICIES).optional().describe('Default progression policy for the routine\'s reps exercises.'),
  why: z.string().max(400).optional().describe('1–2 sentences in Spanish: what this day is for.'),
  ex: z.array(planExercise).min(1).max(20).describe('Exercises in order: compound lifts before accessories; 3–12 is typical.'),
})

const customExercise = z.object({
  id: z.string().min(1).max(40).describe('Your id, e.g. "cx1"; reference it from routines.'),
  n: z.string().min(1).max(60).describe('Exercise name.'),
  bp: z.enum(BODY_PARTS).describe('Body part (English library value); "cardio" makes it a cardio exercise.'),
  desc: z.string().max(400).optional().describe('How to do it, in Spanish.'),
})

const proposePlanInput = z.object({
  name: z.string().min(1).max(40).describe('Short plan name in Spanish, e.g. "Fuerza tres días".'),
  summary: z.string().min(1).max(1200).describe('2–4 sentences in Spanish: the shape of the plan and why it fits what they asked for. When refining, one line names what changed.'),
  basedOn: z.string().max(400).optional().describe('What you used, in Spanish, e.g. "tus últimas 12 semanas" or "sin historial todavía".'),
  week: z.record(z.string(), z.string()).describe('Weekday → routine id from this plan. Keys "0"–"6": 0 = Sunday, 1 = Monday … 6 = Saturday; days left out are rest. At least one day, and exactly athlete.daysPerWeek days once the profile is saved; use athlete.preferredDays when given.'),
  routines: z.array(planRoutine).min(1).max(7).describe('1–7 routines.'),
  customEx: z.array(customExercise).max(20).optional().describe('New custom exercises, only when the library genuinely lacks something. Usually empty.'),
  refines: proposalId.optional().describe('When revising an earlier plan proposal after the owner\'s feedback: its id. Send the complete revised plan; it replaces the pending one with iteration + 1.'),
})

const change = z.object({
  id: z.string().min(1).max(40).describe('Unique id within this proposal, e.g. "c1".'),
  type: z.enum(CHANGE_TYPES).describe(CHANGE_TYPE_GUIDE),
  target: z
    .object({
      routineId: z.string().optional().describe('Routine id from get_overview; every type except add-routine and week.'),
      exId: z.string().optional().describe('Id of an exercise already in that routine.'),
      weekday: z.number().int().min(0).max(6).optional().describe('week only: 0 = Sunday, 1 = Monday … 6 = Saturday.'),
    })
    .optional(),
  before: z.unknown().optional().describe('Optional: the current value as you read it. The server always records the actual current value, and reports it when yours differs.'),
  after: z.unknown().optional().describe('The proposed value; its shape depends on type.'),
  why: z.string().min(1).max(600).describe('1–3 sentences in Spanish naming the evidence: the stall count, the effort trend, the missed days.'),
})

const proposeChangesInput = z.object({
  summary: z.string().min(1).max(1200).describe('2–4 sentences in Spanish: what you saw and what you propose.'),
  evidence: z
    .object({
      from: isoDate.optional().describe('First date you read.'),
      to: isoDate.optional().describe('Last date you read.'),
      sessions: z.number().int().min(0).max(10000).optional().describe('Sessions you read.'),
    })
    .optional()
    .describe('The training you based the changes on, usually get_training_review\'s window.'),
  changes: z.array(change).min(1).max(25).describe('The changes, few and high-conviction: rarely more than about six.'),
  notes: z.array(z.string().min(1).max(600)).max(6).optional().describe('Advice in Spanish with no plan change attached (e.g. body weight moving against the goal, sleep, pain → see a professional).'),
})

const reportNoChangeInput = z.object({
  reading: z.string().trim().min(1).max(1200).describe('A short honest paragraph in Spanish on how the block went and why the plan should stay as it is. The app shows it to the owner.'),
})

/* ------------------------------------------------------------------ helpers */

function portContext(owner: Owner, training: Training): PortContext {
  return {
    catalog: owner.catalog,
    athlete: owner.athlete,
    workingWeights: [...heaviestDoneSets(training)].map(([id, best]) => ({ id, best })),
  }
}

/** Stores a proposal and builds the reply; the shared 30-per-24-hours limit becomes a tool error. */
async function store(db: D1Database, proposal: NewProposal, reply: (stored: ProposalDTO) => object): Promise<CallToolResult> {
  try {
    return jsonResult(reply(await createProposal(db, proposal)))
  } catch (error) {
    if (!(error instanceof ProposalRateLimitError)) throw error
    return errorResult(`Nothing was stored: at most ${PROPOSAL_RATE_LIMIT.max} proposals per 24 hours. Tell the owner and try again later.`)
  }
}

/** Where the `before` Claude sent differs from the plan's actual value (which is what gets stored). */
function corrections(sent: readonly { before?: unknown }[], stored: readonly { id: string; before: unknown }[]) {
  return stored.flatMap((change, i) => {
    const claimed = sent[i]?.before
    return claimed !== undefined && JSON.stringify(claimed) !== JSON.stringify(change.before) ? [{ id: change.id, sent: claimed, actual: change.before }] : []
  })
}

/** A one-line version of a reading for lists. */
function shortSummary(text: string, max = 200): string {
  if (text.length <= max) return text
  const cut = text.slice(0, max - 1)
  const space = cut.lastIndexOf(' ')
  return (space > max / 2 ? cut.slice(0, space) : cut) + '…'
}

/* ------------------------------------------------------------------ tools */

export function registerProposeTools(server: McpServer, db: D1Database): void {
  server.registerTool(
    'propose_plan',
    {
      title: 'Proponer un plan',
      description: `Proposes a complete weekly plan for the owner to review in the app's Coach tab. Nothing changes until they accept it; accepting adds these routines next to their current ones (existing routines are never edited) and, if they choose, replaces the weekly schedule.
Before calling: get_overview (profile, current plan, workingWeights) and search_exercises for ids. Honour athlete.daysPerWeek, preferredDays, sessionMin (about 2–3 minutes per straight set including rest; supersets buy time back), equipment, limitations and dislikes.
The server validates everything and reports every problem at once: known exercise ids only; at least one training day, exactly athlete.daysPerWeek once the profile is saved; mode cardio exactly for cardio exercises; policies valid for each mode; weight only for exercises they have not trained yet, capped at their best. warnings lists exercises whose equipment the athlete did not list. A new plan proposal replaces a pending one. Shares the limit of ${PROPOSAL_RATE_LIMIT.max} proposals per 24 hours.`,
      inputSchema: proposePlanInput,
      annotations: PROPOSES,
    },
    async ({ refines, ...bundle }) => {
      const owner = await loadOwner(db)
      const [training, refined] = await Promise.all([loadTraining(db, owner), refines ? getProposal(db, refines) : null])
      const errors: string[] = []
      if (refines && refined?.kind !== 'plan') errors.push(`refines "${refines}" is not a plan proposal — take the id from list_proposals, or leave refines out for a new plan`)
      const result = validatePlanProposal(bundle, portContext(owner, training))
      if (!result.ok) errors.push(...result.errors)
      if (errors.length || !result.ok) {
        // The original validator's wording points at "the library provided in the payload".
        const unknownIds = errors.some(error => error.includes('is not in the exercise library'))
        const hint = unknownIds ? ' Exercise ids come from search_exercises or get_overview.' : ''
        return errorResult(`The plan was not stored. Fix every problem below and call propose_plan again.${hint}`, errors)
      }

      const { bundle: valid, warnings } = result
      return store(
        db,
        {
          kind: 'plan',
          summary: valid.summary,
          body: { bundle: valid },
          planHash: currentPlanHash(owner.plan, owner.catalog),
          iteration: refined ? refined.iteration + 1 : 1,
        },
        proposal => ({
          proposalId: proposal.id,
          status: proposal.status,
          iteration: proposal.iteration,
          unit: proposal.unit,
          summary: valid.summary,
          routines: valid.routines.map(r => ({
            id: r.id,
            name: r.name,
            exercises: r.ex.length,
            weekdays: MONDAY_FIRST.filter(day => valid.week[day] === r.id).map(day => WEEKDAY_NAMES[day]),
          })),
          warnings,
          message: INERT,
        }),
      )
    },
  )

  server.registerTool(
    'propose_changes',
    {
      title: 'Proponer cambios al plan',
      description: `Proposes specific changes to the current plan, from a closed list of change types. The owner reviews them one by one in the app's Coach tab and accepts any subset; nothing changes before that, and accepted changes can be undone.
Before calling: get_overview (routine and exercise ids, previouslyDeclined) and get_training_review (the evidence). Every change needs a why citing that evidence. Validated against the current plan; every problem is reported at once. The server records each change's before as the plan's actual current value (corrections shows where yours differed) and a fingerprint of the plan, so the app can tell when the plan moved on. warnings lists added exercises whose equipment the athlete did not list. New changes replace pending ones. If nothing should change, call report_no_change instead. Shares the limit of ${PROPOSAL_RATE_LIMIT.max} proposals per 24 hours.`,
      inputSchema: proposeChangesInput,
      annotations: PROPOSES,
    },
    async input => {
      const owner = await loadOwner(db)
      const training = await loadTraining(db, owner)
      const result = validateChangesProposal(input, owner.plan, portContext(owner, training))
      if (!result.ok) return errorResult('The changes were not stored. Fix every problem below and call propose_changes again.', result.errors)
      if ('nochange' in result) return errorResult('No change was proposed. If the plan should stay as it is, call report_no_change with your reading.')

      const { proposal: valid, warnings } = result
      return store(
        db,
        {
          kind: 'changes',
          summary: valid.summary,
          body: { evidence: input.evidence ? valid.evidence : null, changes: valid.changes, notes: valid.notes },
          planHash: currentPlanHash(owner.plan, owner.catalog),
        },
        proposal => ({
          proposalId: proposal.id,
          status: proposal.status,
          unit: proposal.unit,
          summary: valid.summary,
          changes: valid.changes.map(({ id, type, target, before, after }) => ({ id, type, target, before, after })),
          corrections: corrections(input.changes, valid.changes),
          notes: valid.notes,
          warnings,
          message: INERT,
        }),
      )
    },
  )

  server.registerTool(
    'report_no_change',
    {
      title: 'Informar sin cambios',
      description: `Records that, after reviewing their training, the plan should stay as it is. The app shows your reading to the owner as a note. Use it when the plan is working: inventing changes to look useful is the fastest way to lose their trust. It does not replace pending proposals. Shares the limit of ${PROPOSAL_RATE_LIMIT.max} proposals per 24 hours.`,
      inputSchema: reportNoChangeInput,
      annotations: PROPOSES,
    },
    async ({ reading }) => {
      const owner = await loadOwner(db)
      return store(
        db,
        { kind: 'nochange', summary: shortSummary(reading), body: { reading }, planHash: currentPlanHash(owner.plan, owner.catalog) },
        proposal => ({ proposalId: proposal.id, status: proposal.status, reading, message: 'Stored. The owner sees your reading as a note in the Coach tab.' }),
      )
    },
  )
}
