/** Redirect targets Claude uses (contract §5). */
const CLAUDE_CALLBACKS = new Set(['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'])
const CLAUDE_HOSTS = new Set(['claude.ai', 'claude.com'])
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1'])

export function extraRedirectHosts(env: Pick<Env, 'ALLOWED_REDIRECT_HOSTS'>): Set<string> {
  return new Set(
    (env.ALLOWED_REDIRECT_HOSTS ?? '')
      .split(',')
      .map(host => host.trim().toLowerCase())
      .filter(Boolean),
  )
}

/**
 * Whether dynamic client registration may use `uri`: Claude's callbacks, a loopback
 * `http://localhost:<port>/callback` or `http://127.0.0.1:<port>/callback`, or an https URL on a
 * host listed in ALLOWED_REDIRECT_HOSTS.
 */
export function isAllowedRegistrationRedirect(uri: string, extraHosts: ReadonlySet<string>): boolean {
  if (CLAUDE_CALLBACKS.has(uri)) return true
  let url: URL
  try {
    url = new URL(uri)
  } catch {
    return false
  }
  if (url.username || url.password || url.hash) return false
  if (url.protocol === 'http:' && LOOPBACK_HOSTS.has(url.hostname)) return url.pathname === '/callback' && url.search === ''
  return url.protocol === 'https:' && extraHosts.has(url.hostname)
}

/** Whether the consent page may send an authorization to `host` (the redirect URI's hostname). */
export function isAllowedConsentHost(host: string, extraHosts: ReadonlySet<string>): boolean {
  const normalized = host.toLowerCase()
  return CLAUDE_HOSTS.has(normalized) || LOOPBACK_HOSTS.has(normalized) || extraHosts.has(normalized)
}
