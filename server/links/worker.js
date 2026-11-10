// Shotleaf's free screenshot links (s.syvyj.dev): the app uploads a PNG/JPEG, gets a short
// link back, and the picture is gone after at most 12 hours: the link stops at its expiry,
// and the picture is deleted then (on the first visit after it) or by the sweep within 15 minutes.
// Same protocol as the self-hosted server/shots: POST /upload?ttl=SECONDS → 201 {url, expires, delete};
// DELETE /<id> with "Authorization: Bearer <delete>" takes the picture down early.
// Open to anyone (the app is open source, so a key couldn't stay secret): limits instead.

const MAX_BYTES = 5 * 1024 * 1024
const MAX_TTL = 12 * 3600
const SITE = "https://shotleaf.syvyj.dev"
const REPORT = "shotleaf@syvyj.dev"

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (request.method === "POST" && url.pathname === "/upload") return upload(request, env, url)
    if (request.method === "DELETE") return remove(request, env, url)
    if (request.method !== "GET" && request.method !== "HEAD") return json(405, { error: "method not allowed" })
    if (url.pathname === "/") return Response.redirect(SITE, 302)
    const match = url.pathname.match(/^\/([A-Za-z0-9]{8})(\.(png|jpg))?$/)
    return match ? show(env, url, match[1], Boolean(match[2])) : notFound()
  },

  // Cron (wrangler.jsonc): deletes every expired picture. The bucket's one-day lifecycle rule stays as a backstop.
  async scheduled(_event, env) {
    await sweep(env)
  },
}

export async function sweep(env, now = Date.now()) {
  let cursor
  do {
    const page = await env.SHOTS.list({ cursor, include: ["customMetadata"] })
    const expired = page.objects.filter((o) => Number(o.customMetadata?.expires || 0) * 1000 <= now).map((o) => o.key)
    if (expired.length) await env.SHOTS.delete(expired)
    cursor = page.truncated ? page.cursor : undefined
  } while (cursor)
}

async function upload(request, env, url) {
  const ip = request.headers.get("CF-Connecting-IP") || "unknown"
  const { success } = await env.UPLOADS.limit({ key: ip })
  if (!success) return json(429, { error: "too many uploads, try again in a minute" })

  const ttl = Number(url.searchParams.get("ttl") || 6 * 3600)
  if (!Number.isInteger(ttl) || ttl < 60 || ttl > MAX_TTL) return json(400, { error: "links last 1 minute to 12 hours" })
  // The size up front, so an endless body is never read in (the app always sends it).
  const length = Number(request.headers.get("Content-Length"))
  if (!request.headers.get("Content-Length") || !Number.isFinite(length)) return json(411, { error: "length required" })
  if (length > MAX_BYTES) return json(413, { error: "pictures up to 5 MB" })
  const body = await request.arrayBuffer()
  if (body.byteLength === 0 || body.byteLength > MAX_BYTES) return json(413, { error: "pictures up to 5 MB" })
  const type = kind(new Uint8Array(body, 0, Math.min(8, body.byteLength)))
  if (!type) return json(415, { error: "PNG or JPEG only" })

  const id = randomID()
  const expires = Math.floor(Date.now() / 1000) + ttl
  // Only the uploader gets the delete token; the bucket keeps its hash.
  const token = randomID(32)
  await env.SHOTS.put(id, body, { httpMetadata: { contentType: type }, customMetadata: { expires: String(expires), delete: await sha256(token) } })
  return json(201, { url: `${base(url)}/${id}`, expires, delete: token })
}

// The uploader takes the picture down before it expires.
async function remove(request, env, url) {
  const match = url.pathname.match(/^\/([A-Za-z0-9]{8})$/)
  const object = match && (await env.SHOTS.head(match[1]))
  if (!object) return notFound()
  const given = (request.headers.get("Authorization") || "").replace(/^Bearer /, "")
  const hash = object.customMetadata?.delete
  if (!hash || (await sha256(given)) !== hash) return json(403, { error: "wrong delete token" })
  await env.SHOTS.delete(match[1])
  return new Response(null, { status: 204 })
}

async function sha256(text) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return Array.from(new Uint8Array(hash), (b) => b.toString(16).padStart(2, "0")).join("")
}

async function show(env, url, id, raw) {
  const object = raw ? await env.SHOTS.get(id) : await env.SHOTS.head(id)
  const expires = Number(object?.customMetadata?.expires || 0)
  if (!object) return notFound()
  if (expires * 1000 <= Date.now()) {
    await env.SHOTS.delete(id) // gone now, not at the next sweep
    return notFound()
  }
  const left = expires - Math.floor(Date.now() / 1000)
  const headers = { "Cache-Control": `public, max-age=${Math.min(left, 3600)}`, "X-Robots-Tag": "noindex", "X-Content-Type-Options": "nosniff" }
  if (raw) return new Response(object.body, { headers: { ...headers, "Content-Type": object.httpMetadata.contentType } })
  const ext = object.httpMetadata.contentType === "image/png" ? "png" : "jpg"
  const image = `${base(url)}/${id}.${ext}`
  const page = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Screenshot · Shotleaf</title>
<meta property="og:site_name" content="Shotleaf"><meta property="og:title" content="Screenshot">
<meta property="og:description" content="Shared with Shotleaf, screenshots and clipboard history for Mac. The link expires in ${until(left)}.">
<meta property="og:image" content="${image}"><meta name="twitter:card" content="summary_large_image">
<style>body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;background:#f6f7f2;font:14px system-ui;color:#5b6152}
img{max-width:min(96vw,1600px);max-height:86vh;border-radius:10px;box-shadow:0 8px 40px rgba(0,0,0,.15)}a{color:#2d4a19}</style></head>
<body><img src="${image}" alt="Screenshot"><div>Shared with <a href="${SITE}">Shotleaf</a> · gone in ${until(left)} · <a href="mailto:${REPORT}?subject=Report%20${id}">Report</a></div></body></html>`
  return new Response(page, { headers: { ...headers, "Content-Type": "text/html; charset=utf-8" } })
}

function kind(head) {
  if (head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4e && head[3] === 0x47) return "image/png"
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return "image/jpeg"
  return null
}

function randomID(length = 8) {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
  return Array.from(crypto.getRandomValues(new Uint8Array(length)), (b) => abc[b % abc.length]).join("")
}

const json = (status, data) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } })
const notFound = () => new Response("This link has expired or never existed.", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8", "X-Robots-Tag": "noindex" } })
// https on the real domain (a custom domain may hand the Worker http), http only for local runs.
const base = (url) => (url.hostname === "localhost" || url.hostname === "127.0.0.1" ? url.origin : `https://${url.host}`)
const until = (seconds) => (seconds >= 5400 ? `${Math.round(seconds / 3600)} h` : `${Math.max(1, Math.round(seconds / 60))} min`)
