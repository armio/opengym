import { HOUR_MS } from '../lib/time'

export interface Device {
  id: string
  name: string
  createdAt: number
  lastSeenAt: number | null
  tz: string | null
}

interface DeviceRow {
  id: string
  name: string
  created_at: number
  last_seen_at: number | null
  tz: string | null
}

const DEVICE_COLUMNS = 'id, name, created_at, last_seen_at, tz'

function toDevice(row: DeviceRow): Device {
  return { id: row.id, name: row.name, createdAt: row.created_at, lastSeenAt: row.last_seen_at, tz: row.tz }
}

export async function insertDevice(
  db: D1Database,
  device: { id: string; name: string; tokenHash: string; now: number; tz: string | null },
): Promise<void> {
  await db
    .prepare('INSERT INTO devices (id, name, token_hash, created_at, last_seen_at, tz) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(device.id, device.name, device.tokenHash, device.now, device.now, device.tz)
    .run()
}

export async function findDeviceByTokenHash(db: D1Database, tokenHash: string): Promise<Device | null> {
  const row = await db.prepare(`SELECT ${DEVICE_COLUMNS} FROM devices WHERE token_hash = ?`).bind(tokenHash).first<DeviceRow>()
  return row ? toDevice(row) : null
}

/** How often `last_seen_at` is refreshed when nothing else changed. */
export const DEVICE_TOUCH_INTERVAL_MS = HOUR_MS

/**
 * Records that `device` was seen: at most once per hour, or immediately when the reported time
 * zone changed (contract §4.1). `tz` is a validated IANA name or null when none was sent.
 */
export async function touchDevice(db: D1Database, device: Device, now: number, tz: string | null): Promise<void> {
  const tzChanged = tz !== null && tz !== device.tz
  const stale = device.lastSeenAt === null || now - device.lastSeenAt >= DEVICE_TOUCH_INTERVAL_MS
  if (!tzChanged && !stale) return
  await db
    .prepare('UPDATE devices SET last_seen_at = ?, tz = coalesce(?, tz) WHERE id = ?')
    .bind(now, tz, device.id)
    .run()
}

export async function listDevices(db: D1Database): Promise<Device[]> {
  const { results } = await db.prepare(`SELECT ${DEVICE_COLUMNS} FROM devices ORDER BY created_at`).all<DeviceRow>()
  return results.map(toDevice)
}

/** Deletes a device (its token stops working at once); false when no such device exists. */
export async function deleteDevice(db: D1Database, id: string): Promise<boolean> {
  const result = await db.prepare('DELETE FROM devices WHERE id = ?').bind(id).run()
  return result.meta.changes > 0
}

/**
 * The owner's IANA time zone for server-side date math: the zone of the most recently seen device
 * that reported one, else UTC.
 */
export async function ownerTimeZone(db: D1Database): Promise<string> {
  const row = await db
    .prepare('SELECT tz FROM devices WHERE tz IS NOT NULL ORDER BY last_seen_at DESC LIMIT 1')
    .first<{ tz: string }>()
  return row?.tz ?? 'UTC'
}
