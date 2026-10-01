import type { DocCasWrite, DocKey } from '../db/docs'
import { resolveProposal, revertProposal, type ResolveResult } from '../db/proposals'
import { HttpError, jsonResponse, MIB, readJsonBody } from '../lib/http'
import { isPlainObject, isStringArray, type JsonObject } from '../lib/json'
import type { DeviceContext } from './context'
import { ItemError, parseDocWrite } from './syncInput'

/** Docs a resolve or revert may write: the plan and the coach log (contract §4.3). */
const PROPOSAL_DOC_KEYS: readonly DocKey[] = ['plan', 'coach']

function bodyObject(body: unknown): JsonObject {
  if (!isPlainObject(body)) throw new HttpError(400, 'El cuerpo debe ser un objeto JSON.')
  return body
}

function docWritesOf(value: unknown, now: number): DocCasWrite[] {
  if (value === undefined) return []
  if (!Array.isArray(value)) throw new HttpError(400, '`docs` debe ser una lista.')
  const writes: DocCasWrite[] = []
  for (const item of value) {
    let write: DocCasWrite
    try {
      write = parseDocWrite(item, now, { requireUpdatedAt: false })
    } catch (error) {
      if (error instanceof ItemError) throw new HttpError(400, `Documento no válido: ${error.message}.`)
      throw error
    }
    if (!PROPOSAL_DOC_KEYS.includes(write.key)) throw new HttpError(400, `No se puede escribir «${write.key}» al resolver una propuesta.`)
    if (writes.some(other => other.key === write.key)) throw new HttpError(400, `«${write.key}» aparece dos veces.`)
    writes.push(write)
  }
  return writes
}

function idsOf(body: JsonObject, field: 'accepted' | 'rejected' | 'stale'): string[] {
  const value = body[field]
  if (value === undefined) return []
  if (!isStringArray(value)) throw new HttpError(400, `\`${field}\` debe ser una lista de ids.`)
  return value
}

const CONFLICT_MESSAGES = {
  'not-pending': 'Esta propuesta ya no está pendiente.',
  'not-applied': 'Solo se puede deshacer una propuesta aplicada.',
  'docs-changed': 'Tus datos cambiaron en otro dispositivo. Sincroniza y vuelve a intentarlo.',
} as const

function resultResponse(result: ResolveResult): Response {
  switch (result.status) {
    case 'ok':
      return jsonResponse({ proposal: result.proposal, docs: result.docs })
    case 'conflict':
      throw new HttpError(409, CONFLICT_MESSAGES[result.reason], { proposal: result.proposal })
    case 'not-found':
      throw new HttpError(404, 'Propuesta no encontrada.')
  }
}

/** `POST /api/proposals/:id/resolve`: accept or dismiss atomically with the doc writes (contract §4.3). */
export async function resolve({ request, env, params, now }: DeviceContext): Promise<Response> {
  const body = bodyObject(await readJsonBody(request, 2 * MIB))
  if (body.outcome !== 'applied' && body.outcome !== 'dismissed') {
    throw new HttpError(400, '`outcome` debe ser "applied" o "dismissed".')
  }
  if (body.schedule !== undefined && typeof body.schedule !== 'boolean') throw new HttpError(400, '`schedule` debe ser booleano.')
  const result = await resolveProposal(
    env.DB,
    params[0]!,
    {
      outcome: body.outcome,
      accepted: idsOf(body, 'accepted'),
      rejected: idsOf(body, 'rejected'),
      stale: idsOf(body, 'stale'),
      ...(body.schedule !== undefined && { schedule: body.schedule }),
      docs: docWritesOf(body.docs, now),
    },
    now,
  )
  return resultResponse(result)
}

/** `POST /api/proposals/:id/revert`: restore the plan and pop the snapshot atomically (contract §4.3). */
export async function revert({ request, env, params, now }: DeviceContext): Promise<Response> {
  const body = bodyObject(await readJsonBody(request, 2 * MIB))
  return resultResponse(await revertProposal(env.DB, params[0]!, { docs: docWritesOf(body.docs, now) }, now))
}
