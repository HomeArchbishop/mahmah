/** 开发时经 Vite 代理到 zig :8080 */
export function wsUrl (path: string): string {
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  const base = path.startsWith('/') ? path : `/${path}`
  return `${proto}//${window.location.host}${base}`
}
