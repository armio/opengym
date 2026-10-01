/**
 * The rate-limit key of a request (contract §4.1): the `CF-Connecting-IP` address, with IPv6
 * truncated to its /64 so one host cannot rotate through its subnet.
 */
export function clientKey(request: Request): string {
  const ip = request.headers.get('CF-Connecting-IP')?.trim()
  if (!ip) return 'unknown'
  return ip.includes(':') ? ipv6Prefix64(ip) : ip
}

function ipv6Prefix64(ip: string): string {
  const address = ip.replace(/^\[|\]$/g, '').split('%')[0]!.toLowerCase()
  const [head = '', tail] = address.split('::')
  const headGroups = head ? head.split(':') : []
  const tailGroups = tail ? tail.split(':') : []
  // An embedded IPv4 suffix only affects the low 64 bits, which are discarded anyway.
  const missing = Math.max(0, 8 - headGroups.length - tailGroups.length)
  const groups = tail === undefined ? headGroups : [...headGroups, ...Array(missing).fill('0'), ...tailGroups]
  const prefix = groups.slice(0, 4).map(group => (parseInt(group, 16) || 0).toString(16))
  while (prefix.length < 4) prefix.push('0')
  return `${prefix.join(':')}::/64`
}
