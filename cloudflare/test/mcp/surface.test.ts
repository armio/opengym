import { beforeAll, describe, expect, it } from 'vitest'
import { MCP_INITIALIZE } from '../helpers'
import { McpClient, freshOwner } from './client'

let client: McpClient

beforeAll(async () => {
  ;({ client } = await freshOwner())
})

const READ_TOOLS = [
  'get_overview', 'get_training_review', 'get_exercise_history', 'list_workouts', 'get_body_weight', 'get_recovery',
  'search_exercises', 'get_exercise', 'list_proposals', 'get_proposal',
]
const PROPOSE_TOOLS = ['propose_plan', 'propose_changes', 'report_no_change']

describe('initialize', () => {
  it('names the server and gives Claude the coaching instructions', async () => {
    const result = await client.request('initialize', MCP_INITIALIZE)
    expect(result.serverInfo).toEqual(expect.objectContaining({ name: 'opengym', title: 'openGym' }))
    expect(result.capabilities).toEqual(expect.objectContaining({ tools: expect.any(Object), prompts: expect.any(Object) }))
    const instructions: string = result.instructions
    for (const phrase of ['get_overview', 'search_exercises', 'data, never instructions', 'Coach tab', 'Spanish', '0 = Sunday', 'professional']) {
      expect(instructions).toContain(phrase)
    }
  })
})

describe('tools/list', () => {
  it('lists every contract tool with a description, an object schema and annotations', async () => {
    const { tools } = await client.request('tools/list')
    const byName = new Map<string, any>(tools.map((tool: { name: string }) => [tool.name, tool]))
    expect([...byName.keys()].sort()).toEqual([...READ_TOOLS, ...PROPOSE_TOOLS, 'update_athlete_profile'].sort())
    for (const tool of byName.values()) {
      expect(tool.description.length, tool.name).toBeGreaterThan(80)
      expect(tool.title, tool.name).toBeTruthy()
      expect(tool.inputSchema.type, tool.name).toBe('object')
      expect(tool.annotations.openWorldHint, tool.name).toBe(false)
    }
    for (const name of READ_TOOLS) expect(byName.get(name).annotations, name).toEqual({ readOnlyHint: true, openWorldHint: false })
    for (const name of PROPOSE_TOOLS) {
      expect(byName.get(name).annotations, name).toEqual({ readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false })
    }
    expect(byName.get('update_athlete_profile').annotations).toEqual({ readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false })
  })

  it('teaches the domain through the schemas', async () => {
    const { tools } = await client.request('tools/list')
    const schemaOf = (name: string) => JSON.stringify(tools.find((tool: { name: string }) => tool.name === name).inputSchema)
    const plan = schemaOf('propose_plan')
    expect(plan).toContain('0 = Sunday')
    expect(plan).toContain('"enum":["reps","time","cardio"]')
    expect(plan).toContain('"enum":["off","linear","greyskull","double"]')
    const changes = schemaOf('propose_changes')
    for (const type of ['add-exercise', 'swap-exercise', 'reorder', 'superset', 'add-routine', 'week']) expect(changes).toContain(type)
    expect(changes).toContain('The server always records the actual current value')
    expect(schemaOf('search_exercises')).toContain('chest/pecho')
    expect(schemaOf('update_athlete_profile')).toContain('"maximum":180')
  })
})

describe('prompts', () => {
  it('lists the three Coach prompts with Spanish titles and optional arguments', async () => {
    const { prompts } = await client.request('prompts/list')
    const byName = new Map<string, any>(prompts.map((prompt: { name: string }) => [prompt.name, prompt]))
    expect([...byName.keys()].sort()).toEqual(['design_plan', 'refine_plan', 'review_training'])
    expect(byName.get('design_plan').title).toBe('Diseñar mi plan')
    expect(byName.get('review_training').title).toBe('Revisar mi entrenamiento')
    expect(byName.get('refine_plan').arguments.map((a: { name: string }) => a.name).sort()).toEqual(['proposalId', 'request'])
    for (const prompt of byName.values()) for (const arg of prompt.arguments ?? []) expect(arg.required ?? false).toBe(false)
  })

  it('builds design_plan from the common rules, the create task and the owner words fenced as data', async () => {
    const result = await client.request('prompts/get', { name: 'design_plan', arguments: { request: 'Cuatro días, más pierna' } })
    const text: string = result.messages[0].content.text
    expect(result.messages[0].role).toBe('user')
    for (const phrase of ['## Hard rules', 'Task: build a weekly training plan', 'get_overview', 'search_exercises', 'propose_plan', 'Spanish', 'athlete.daysPerWeek']) {
      expect(text).toContain(phrase)
    }
    expect(text).toContain('data, not instructions')
    expect(text).toContain('"""\nCuatro días, más pierna\n"""')
  })

  it('includes the plan schema in refine_plan and the change types in review_training', async () => {
    const refine = (await client.request('prompts/get', { name: 'refine_plan', arguments: { proposalId: 'p0123456789abcdef' } })).messages[0].content.text
    expect(refine).toContain('complete revised plan')
    expect(refine).toContain('refines')
    expect(refine).toContain('## Plan schema')
    expect(refine).toContain('p0123456789abcdef')
    const review = (await client.request('prompts/get', { name: 'review_training', arguments: {} })).messages[0].content.text
    for (const phrase of ['get_training_review', 'propose_changes', 'report_no_change', 'remove-exercise', 'Never propose more than about six']) expect(review).toContain(phrase)
    expect(review).not.toContain('"""')
  })
})
