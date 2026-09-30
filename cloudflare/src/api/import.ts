import { writeImport } from '../db/bulk'
import { ownerTimeZone } from '../db/devices'
import { isOpenGymState, mapOpenGymBackup } from '../import/opengym'
import { HttpError, jsonResponse, MIB, readJsonBody } from '../lib/http'
import { byteLength, isPlainObject } from '../lib/json'
import { MAX_DOC_BYTES } from '../lib/rules'
import type { DeviceContext } from './context'

/** `POST /api/import/opengym { state, mode }` (contract §4.4). */
export async function importOpenGym({ request, env, now }: DeviceContext): Promise<Response> {
  const body = await readJsonBody(request, 20 * MIB)
  if (!isPlainObject(body) || !isOpenGymState(body.state)) throw new HttpError(400, 'No es una copia de openGym')
  const mode = body.mode ?? 'replace'
  if (mode !== 'replace' && mode !== 'merge') throw new HttpError(400, '`mode` debe ser "replace" o "merge".')

  const backup = mapOpenGymBackup(body.state, { now, timeZone: await ownerTimeZone(env.DB) })
  const oversized = backup.docs.find(doc => byteLength(JSON.stringify(doc.data)) > MAX_DOC_BYTES)
  if (oversized) throw new HttpError(400, `La copia es demasiado grande: «${oversized.key}» supera ${MAX_DOC_BYTES / 1024} KiB.`)
  await writeImport(env.DB, backup, mode, now)
  return jsonResponse({
    imported: { workouts: backup.workouts.length, bodyweight: backup.bodyweight.length, routines: backup.routineCount },
  })
}
