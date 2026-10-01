import { deleteDevice, listDevices as listStoredDevices } from '../db/devices'
import { HttpError, jsonResponse } from '../lib/http'
import type { DeviceContext } from './context'

/** `GET /api/devices` → `[{ id, name, createdAt, lastSeenAt, current }]`. */
export async function listDevices({ env, device }: DeviceContext): Promise<Response> {
  const devices = await listStoredDevices(env.DB)
  return jsonResponse(
    devices.map(d => ({ id: d.id, name: d.name, createdAt: d.createdAt, lastSeenAt: d.lastSeenAt, current: d.id === device.id })),
  )
}

/** `POST /api/devices/:id/revoke`: signs a device out; its token stops working at once. */
export async function revokeDevice({ env, params }: DeviceContext): Promise<Response> {
  if (!(await deleteDevice(env.DB, params[0]!))) throw new HttpError(404, 'Dispositivo no encontrado.')
  return jsonResponse({ ok: true })
}
