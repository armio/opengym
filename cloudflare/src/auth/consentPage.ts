import type { ConsentDescription } from '@cloudflare/workers-oauth-provider'

/** Escapes text for HTML content and attribute values. */
export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, char => `&#${char.charCodeAt(0)};`)
}

const STYLES = `
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px 16px;
         background: #000; color: #f2f2f7; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { width: 100%; max-width: 420px; background: #1c1c1e; border-radius: 16px; padding: 28px 24px; }
  .brand { color: #30d158; font-weight: 700; letter-spacing: .02em; margin: 0 0 12px; }
  h1 { font-size: 21px; line-height: 1.3; margin: 0 0 16px; }
  p { margin: 0 0 12px; color: #d1d1d6; }
  strong { color: #fff; }
  .warning { background: #3a2a00; color: #ffd60a; border-radius: 10px; padding: 10px 12px; }
  .error { background: #3a0d0b; color: #ff6961; border-radius: 10px; padding: 10px 12px; }
  label { display: block; margin: 20px 0 6px; font-size: 14px; color: #aeaeb2; }
  input[type=password] { width: 100%; padding: 12px; border-radius: 10px; border: 1px solid #3a3a3c;
                         background: #2c2c2e; color: #fff; font-size: 16px; }
  /* Permitir comes first in the DOM so Enter submits it; it is shown on the right. */
  .actions { display: flex; flex-direction: row-reverse; gap: 12px; margin-top: 20px; }
  button { flex: 1; padding: 12px; border: 0; border-radius: 10px; font-size: 16px; font-weight: 600; cursor: pointer; }
  .allow { background: #30d158; color: #000; }
  .deny { background: #3a3a3c; color: #fff; }
  .fine { font-size: 13px; color: #8e8e93; margin-top: 16px; }
`

function layout(title: string, body: string): string {
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(title)}</title>
<style>${STYLES}</style>
</head>
<body><main>
<p class="brand">openGym</p>
${body}
</main></body>
</html>`
}

export interface ConsentView {
  details: ConsentDescription
  handle: string
  error?: string
}

/** The consent page: who is asking, where the access goes, the owner password, Permitir / Denegar. */
export function renderConsentPage({ details, handle, error }: ConsentView): string {
  const name = escapeHtml(details.clientName)
  const origin = details.clientDomain
    ? `<p>Publicada por <strong>${escapeHtml(details.clientDomain)}</strong>.</p>`
    : '<p>Esta aplicación se registró sola; su nombre no está verificado.</p>'
  const loopback = details.redirectIsLoopback
    ? '<p class="warning">Esto envía el acceso a una aplicación de este ordenador. Continúa solo si acabas de iniciar la conexión desde ella.</p>'
    : ''
  const failure = error ? `<p class="error" role="alert">${escapeHtml(error)}</p>` : ''
  return layout(
    `Autorizar ${details.clientName}`,
    `<h1>¿Permitir que <strong>${name}</strong> acceda a tu openGym?</h1>
${origin}
<p>El acceso se enviará a <strong>${escapeHtml(details.redirectHost)}</strong>.</p>
${loopback}
<p>Podrá leer tus entrenos, tu plan, tu peso corporal y tu perfil de atleta, actualizar tu perfil y proponerte planes y cambios que tú aceptas o rechazas en la app.</p>
${failure}
<form method="post">
  <input type="hidden" name="handle" value="${escapeHtml(handle)}">
  <label for="password">Contraseña del servidor</label>
  <input id="password" name="password" type="password" autocomplete="current-password" required autofocus>
  <div class="actions">
    <button class="allow" type="submit" name="decision" value="approve">Permitir</button>
    <button class="deny" type="submit" name="decision" value="deny" formnovalidate>Denegar</button>
  </div>
</form>
<p class="fine">No se recuerda este permiso: se pedirá cada vez. Puedes revocarlo en la app, en Ajustes.</p>`,
  )
}

/** A page with a title and a message, for errors that must not redirect. */
export function renderMessagePage(title: string, message: string): string {
  return layout(title, `<h1>${escapeHtml(title)}</h1>\n<p>${escapeHtml(message)}</p>`)
}
