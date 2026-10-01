export type JsonObject = Record<string, unknown>

export function isPlainObject(value: unknown): value is JsonObject {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false
  const proto = Object.getPrototypeOf(value)
  return proto === Object.prototype || proto === null
}

const encoder = new TextEncoder()

export function byteLength(text: string): number {
  return encoder.encode(text).byteLength
}

/** Parses a JSON column that the Worker itself wrote; corrupt data surfaces as an empty object. */
export function parseJsonObject(text: string | null | undefined): JsonObject {
  if (!text) return {}
  try {
    const value: unknown = JSON.parse(text)
    return isPlainObject(value) ? value : {}
  } catch {
    return {}
  }
}

export function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(item => typeof item === 'string')
}
