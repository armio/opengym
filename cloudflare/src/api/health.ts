import { jsonResponse } from '../lib/http'
import { APP_VERSION } from '../version'

/** `GET /api/health`: liveness only, no counts (data-B14). */
export function health(): Response {
  return jsonResponse({ ok: true, version: APP_VERSION })
}
