import { sha256 } from '../lib/ids'

export const MIN_PASSWORD_LENGTH = 12

export const MISCONFIGURED_PASSWORD_MESSAGE = 'Servidor mal configurado: define OWNER_PASSWORD (mínimo 12 caracteres)'

export function ownerPasswordConfigured(env: Pick<Env, 'OWNER_PASSWORD'>): boolean {
  return typeof env.OWNER_PASSWORD === 'string' && env.OWNER_PASSWORD.length >= MIN_PASSWORD_LENGTH
}

/**
 * Compares `candidate` with OWNER_PASSWORD in constant time: both are hashed first, so neither
 * the content nor the length of the secret leaks through timing.
 */
export async function isOwnerPassword(env: Pick<Env, 'OWNER_PASSWORD'>, candidate: string): Promise<boolean> {
  if (!ownerPasswordConfigured(env)) return false
  const [expected, actual] = await Promise.all([sha256(env.OWNER_PASSWORD!), sha256(candidate)])
  return crypto.subtle.timingSafeEqual(expected, actual)
}
