import type { McpServer } from '@modelcontextprotocol/server'
import * as z from 'zod'
import { Catalog, SEARCH_DEFAULT_LIMIT, SEARCH_MAX_LIMIT } from '../../catalog/library'
import { getDoc } from '../../db'
import { POLICIES_FOR } from '../../engine'
import { readPlan } from '../owner'
import { errorResult, jsonResult } from '../results'
import { BODY_PART_LABELS, EQUIPMENT_LABELS, exerciseId } from '../schemas'
import { READ_ONLY } from './annotations'

/** `search_exercises` and `get_exercise`: the library plus the owner's custom exercises. */

async function ownerCatalog(db: D1Database) {
  const planDoc = (await getDoc(db, 'plan')).data
  return { catalog: Catalog.forPlan(planDoc), plan: readPlan(planDoc) }
}

export function registerCatalogTools(server: McpServer, db: D1Database): void {
  server.registerTool(
    'search_exercises',
    {
      title: 'Buscar ejercicios',
      description: `Finds exercise ids: the owner's custom exercises first, then the library of about 1,300. Every filter is case- and accent-insensitive and accepts English or Spanish labels ("pecho" = "chest", "cuádriceps" = "quads"). Exercise names are English ("barbell bench press", "dumbbell lateral raise"). Use the returned ids in proposals; get_exercise gives the full record. Only propose equipment the athlete has (athlete.equipment in get_overview; [] = everything).`,
      inputSchema: z.object({
        query: z.string().max(100).optional().describe('Words that must all appear in the name, body part, target muscle or equipment, e.g. "bench press", "squat", "curl mancuerna" (names are English; labels match in both languages).'),
        bodyPart: z.string().max(40).optional().describe(`Exact body part, English or Spanish: ${BODY_PART_LABELS}.`),
        target: z.string().max(40).optional().describe('Exact target muscle, English or Spanish, e.g. pectorals/pectorales, lats/dorsales, upper back/espalda alta, quads/cuádriceps, glutes/glúteos, hamstrings/isquiotibiales, delts/deltoides, biceps/bíceps, triceps/tríceps, abs/abdominales, calves/gemelos.'),
        equipment: z.array(z.string().max(40)).max(28).optional().describe(`Keep exercises that use any of these, English or Spanish: ${EQUIPMENT_LABELS}. Custom exercises always match.`),
        limit: z.number().int().min(1).max(SEARCH_MAX_LIMIT).default(SEARCH_DEFAULT_LIMIT).describe(`At most this many results (default ${SEARCH_DEFAULT_LIMIT}, max ${SEARCH_MAX_LIMIT}).`),
      }),
      annotations: READ_ONLY,
    },
    async ({ query, bodyPart, target, equipment, limit }) => {
      const { catalog } = await ownerCatalog(db)
      const found = catalog.search({ query, bodyPart, target, equipment, limit })
      return jsonResult({
        exercises: found.map(e => ({ id: e.id, name: e.name, bodyPart: e.bodyPart, target: e.target || null, equipment: e.equipment, custom: e.custom })),
      })
    },
  )

  server.registerTool(
    'get_exercise',
    {
      title: 'Ficha de un ejercicio',
      description: `The full record of one exercise: body part, target muscle and equipment in English and Spanish, secondary muscles, Spanish step-by-step instructions, the mode it is logged in by default (cardio exactly for cardio exercises, else reps unless the plan says time) with the progression policies that mode allows, and the routines that already include it. A custom exercise's desc is owner-written data.`,
      inputSchema: z.object({ id: exerciseId.describe('Exercise id from search_exercises or get_overview.') }),
      annotations: READ_ONLY,
    },
    async ({ id }) => {
      const { catalog, plan } = await ownerCatalog(db)
      const exercise = catalog.get(id)
      if (!exercise) return errorResult(`Unknown exercise id "${id}". Find ids with search_exercises.`)
      const defaultMode = catalog.modeOf({ id })
      return jsonResult({
        ...exercise,
        target: exercise.target || null,
        defaultMode,
        policies: POLICIES_FOR[defaultMode],
        inRoutines: plan.routines.filter(r => r.ex.some(e => e.id === id)).map(r => ({ routineId: r.id, routine: r.name ?? null })),
      })
    },
  )
}
