import type { JsonObject } from './json'

const NO_STORE = { 'Cache-Control': 'no-store' }

export function jsonResponse(body: unknown, status = 200, headers?: HeadersInit): Response {
  const response = Response.json(body, { status, headers: NO_STORE })
  if (headers) new Headers(headers).forEach((value, name) => response.headers.set(name, value))
  return response
}

/** An error that maps to a JSON `{ error }` response; `extra` adds fields such as `proposal`. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly extra: JsonObject = {},
    readonly headers: HeadersInit = {},
  ) {
    super(message)
  }

  toResponse(): Response {
    return jsonResponse({ error: this.message, ...this.extra }, this.status, this.headers)
  }
}

export const KIB = 1024
export const MIB = 1024 * KIB

/** True when the request declares a JSON body (`application/json`, any parameters). */
export function hasJsonContentType(request: Request): boolean {
  const type = request.headers.get('Content-Type')
  return type !== null && type.split(';')[0]!.trim().toLowerCase() === 'application/json'
}

async function readBodyText(request: Request, maxBytes: number): Promise<string> {
  const tooLarge = () => new HttpError(413, 'La petición es demasiado grande.')
  const declared = Number(request.headers.get('Content-Length'))
  if (Number.isFinite(declared) && declared > maxBytes) throw tooLarge()
  if (!request.body) return ''
  const reader = request.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    total += value.byteLength
    if (total > maxBytes) {
      await reader.cancel()
      throw tooLarge()
    }
    chunks.push(value)
  }
  const bytes = new Uint8Array(total)
  let offset = 0
  for (const chunk of chunks) {
    bytes.set(chunk, offset)
    offset += chunk.byteLength
  }
  return new TextDecoder().decode(bytes)
}

/** Reads and parses a JSON body of at most `maxBytes`; an empty body reads as `{}`. */
export async function readJsonBody(request: Request, maxBytes: number): Promise<unknown> {
  const text = await readBodyText(request, maxBytes)
  if (text.trim() === '') return {}
  try {
    return JSON.parse(text)
  } catch {
    throw new HttpError(400, 'El cuerpo de la petición no es JSON válido.')
  }
}
