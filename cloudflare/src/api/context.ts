import type { Device } from '../db/devices'

export interface ApiContext {
  request: Request
  env: Env
  url: URL
  /** Captured path segments of the matched route. */
  params: string[]
  now: number
}

export interface DeviceContext extends ApiContext {
  device: Device
  /** The raw bearer token's SHA-256, identifying the calling device. */
  tokenHash: string
}

export type Handler<C extends ApiContext = ApiContext> = (context: C) => Promise<Response> | Response
