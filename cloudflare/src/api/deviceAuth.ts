import { findDeviceByTokenHash, touchDevice } from '../db/devices'
import { HttpError } from '../lib/http'
import { sha256Hex } from '../lib/ids'
import { isValidTimeZone } from '../lib/time'
import type { ApiContext, DeviceContext } from './context'

const BEARER = /^Bearer[\t ]+(\S+)$/i

export function unauthorized(): HttpError {
  return new HttpError(401, 'Sesión no válida o caducada. Inicia sesión de nuevo.', {}, { 'WWW-Authenticate': 'Bearer' })
}

/** The IANA zone in `X-Timezone`, or null when absent or not a real zone. */
export function requestTimeZone(request: Request): string | null {
  const tz = request.headers.get('X-Timezone')?.trim()
  return isValidTimeZone(tz) ? tz : null
}

/** Resolves `Authorization: Bearer <device token>` to its device and records the visit (contract §4.1). */
export async function authenticateDevice(context: ApiContext): Promise<DeviceContext> {
  const token = BEARER.exec(context.request.headers.get('Authorization') ?? '')?.[1]
  if (!token) throw unauthorized()
  const tokenHash = await sha256Hex(token)
  const device = await findDeviceByTokenHash(context.env.DB, tokenHash)
  if (!device) throw unauthorized()
  await touchDevice(context.env.DB, device, context.now, requestTimeZone(context.request))
  return { ...context, device, tokenHash }
}
