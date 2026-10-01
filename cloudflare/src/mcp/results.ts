import type { CallToolResult } from '@modelcontextprotocol/server'

/**
 * Tool results (contract §5.2): always a JSON object, sent as text for every client and as
 * `structuredContent` for clients that read it.
 */

export function jsonResult(value: object): CallToolResult {
  return { content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value as Record<string, unknown> }
}

/**
 * A failed call Claude can correct and retry: the message, then every problem on its own line
 * (validation reports all of them at once, never just the first).
 */
export function errorResult(message: string, errors: readonly string[] = []): CallToolResult {
  const text = errors.length ? `${message}\n${errors.map(error => `- ${error}`).join('\n')}` : message
  return {
    content: [{ type: 'text', text }],
    structuredContent: { error: message, ...(errors.length ? { errors: [...errors] } : {}) },
    isError: true,
  }
}
