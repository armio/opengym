import type { ToolAnnotations } from '@modelcontextprotocol/server'

/** Tool annotations (contract §5.2). No tool reaches outside the owner's own data. */

/** Reads only; never writes, not even proposal expiry. */
export const READ_ONLY: ToolAnnotations = { readOnlyHint: true, openWorldHint: false }

/** Stores a new proposal each call; nothing changes until the owner accepts it in the app. */
export const PROPOSES: ToolAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }

/** Overwrites profile fields; repeating the same call leaves the same profile. */
export const OVERWRITES_PROFILE: ToolAnnotations = { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false }
