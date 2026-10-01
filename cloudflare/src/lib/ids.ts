function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('')
}

export function randomHex(byteCount: number): string {
  return toHex(crypto.getRandomValues(new Uint8Array(byteCount)))
}

export function base64url(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))
}

export async function sha256Hex(text: string): Promise<string> {
  return toHex(await sha256(text))
}

/** 'd' + 16 hex. */
export const newDeviceId = (): string => 'd' + randomHex(8)

/** 'p' + 16 hex. */
export const newProposalId = (): string => 'p' + randomHex(8)

/** A device bearer token: 32 random bytes, base64url. */
export const newDeviceToken = (): string => base64url(crypto.getRandomValues(new Uint8Array(32)))
