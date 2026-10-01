import { clientKey } from '../auth/clientKey'
import { isOwnerPassword, MISCONFIGURED_PASSWORD_MESSAGE, ownerPasswordConfigured } from '../auth/password'
import { clearAuthAttempt, recordAuthAttempt } from '../db/authFailures'
import { deleteDevice, insertDevice } from '../db/devices'
import { HttpError, jsonResponse, KIB, readJsonBody } from '../lib/http'
import { newDeviceId, newDeviceToken, sha256Hex } from '../lib/ids'
import { isPlainObject } from '../lib/json'
import type { ApiContext, DeviceContext } from './context'
import { requestTimeZone } from './deviceAuth'

const DEFAULT_DEVICE_NAME = 'Dispositivo'
const MAX_DEVICE_NAME = 60

function deviceNameFrom(value: unknown): string {
  const name = typeof value === 'string' ? value.trim() : ''
  return name ? Array.from(name).slice(0, MAX_DEVICE_NAME).join('') : DEFAULT_DEVICE_NAME
}

/** `POST /api/auth/login { password, deviceName }` → `{ token, deviceId }` (contract §4.1). */
export async function login({ request, env, now }: ApiContext): Promise<Response> {
  const body = await readJsonBody(request, 16 * KIB)
  if (!isPlainObject(body) || typeof body.password !== 'string') throw new HttpError(400, 'Falta la contraseña.')
  if (!ownerPasswordConfigured(env)) throw new HttpError(500, MISCONFIGURED_PASSWORD_MESSAGE)

  const attempt = await recordAuthAttempt(env.DB, clientKey(request), now)
  if (attempt.limited) {
    throw new HttpError(429, 'Demasiados intentos. Espera unos minutos y vuelve a probar.', {}, { 'Retry-After': '900' })
  }
  if (!(await isOwnerPassword(env, body.password))) throw new HttpError(401, 'Contraseña incorrecta.')
  await clearAuthAttempt(env.DB, attempt.id)

  const token = newDeviceToken()
  const deviceId = newDeviceId()
  await insertDevice(env.DB, {
    id: deviceId,
    name: deviceNameFrom(body.deviceName),
    tokenHash: await sha256Hex(token),
    now,
    tz: requestTimeZone(request),
  })
  return jsonResponse({ token, deviceId })
}

/** `POST /api/auth/logout`: revokes the calling device. */
export async function logout({ env, device }: DeviceContext): Promise<Response> {
  await deleteDevice(env.DB, device.id)
  return jsonResponse({ ok: true })
}
