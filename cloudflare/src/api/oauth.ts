import { OWNER_USER_ID } from '../auth/consent'
import { jsonResponse } from '../lib/http'
import type { DeviceContext } from './context'

/** `POST /api/oauth/revoke-all`: revokes every grant Claude holds, with its tokens. */
export async function revokeAllGrants({ env }: DeviceContext): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER
  let revoked = 0
  let cursor: string | undefined
  do {
    const page = await oauth.listUserGrants(OWNER_USER_ID, cursor ? { cursor } : {})
    for (const grant of page.items) {
      await oauth.revokeGrant(grant.id, OWNER_USER_ID)
      revoked++
    }
    cursor = page.cursor
  } while (cursor)
  return jsonResponse({ ok: true, revoked })
}
