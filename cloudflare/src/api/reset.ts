import { resetAllData } from '../db/bulk'
import { HttpError, jsonResponse, KIB, readJsonBody } from '../lib/http'
import { isPlainObject } from '../lib/json'
import type { DeviceContext } from './context'

/** `POST /api/reset { confirm: 'RESET' }`: erase all training data (contract §4.6). */
export async function reset({ request, env, now }: DeviceContext): Promise<Response> {
  const body = await readJsonBody(request, KIB)
  if (!isPlainObject(body) || body.confirm !== 'RESET') throw new HttpError(400, 'Para borrar todo, envía { "confirm": "RESET" }.')
  return jsonResponse({ ok: true, seq: await resetAllData(env.DB, now) })
}
