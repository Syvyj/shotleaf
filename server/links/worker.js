// Shotleaf's free screenshot links (s.syvyj.dev): the app uploads a PNG/JPEG, gets a short
// link back, and the picture is gone after at most 12 hours.
// Same protocol as the self-hosted server/shots: POST /upload?ttl=SECONDS → 201 {url, expires}.
// Open to anyone (the app is open source, so a key couldn't stay secret): limits instead.

const MAX_BYTES = 5 * 1024 * 1024
const MAX_TTL = 12 * 3600
const SITE = "https://shotleaf.syvyj.dev"
const REPORT = "shotleaf@syvyj.dev"

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (request.method === "POST" && url.pathname === "/upload") return upload(request, env, url)
    if (request.method !== "GET" && request.method !== "HEAD") return json(405, { error: "method not allowed" })
    if (url.pathname === "/") return Response.redirect(SITE, 302)
    const match = url.pathname.match(/^\/([A-Za-z0-9]{8})(\.(png|jpg))?$/)
    return match ? show(env, url, match[1], Boolean(match[2])) : notFound()
  },
}

async function upload(request, env, url) {
  const ip = request.headers.get("CF-Connecting-IP") || "unknown"
  const { success } = await env.UPLOADS.limit({ key: ip })
  if (!success) return json(429, { error: "too many uploads, try again in a minute" })

  const ttl = Number(url.searchParams.get("ttl") || 6 * 3600)
  if (!Number.isInteger(ttl) || ttl < 60 || ttl > MAX_TTL) return json(400, { error: "links last 1 minute to 12 hours" })
  const length = Number(request.headers.get("Content-Length") || 0)
  if (length > MAX_BYTES) return json(413, { error: "pictures up to 5 MB" })
  const body = await request.arrayBuffer()
  if (body.byteLength === 0 || body.byteLength > MAX_BYTES) return json(413, { error: "pictures up to 5 MB" })
  const type = kind(new Uint8Array(body, 0, Math.min(8, body.byteLength)))
  if (!type) return json(415, { error: "PNG or JPEG only" })

  const id = randomID()
  const expires = Math.floor(Date.now() / 1000) + ttl
  await env.SHOTS.put(id, body, { httpMetadata: { contentType: type }, customMetadata: { expires: String(expires) } })
  return json(201, { url: `${base(url)}/${id}`, expires })
}

async function show(env, url, id, raw) {
  const object = raw ? await env.SHOTS.get(id) : await env.SHOTS.head(id)
  const expires = Number(object?.customMetadata?.expires || 0)
  if (!object || expires * 1000 <= Date.now()) return notFound() // the bucket's lifecycle rule deletes it within a day
  const left = expires - Math.floor(Date.now() / 1000)
  const headers = { "Cache-Control": `public, max-age=${Math.min(left, 3600)}`, "X-Robots-Tag": "noindex", "X-Content-Type-Options": "nosniff" }
  if (raw) return new Response(object.body, { headers: { ...headers, "Content-Type": object.httpMetadata.contentType } })
  const ext = object.httpMetadata.contentType === "image/png" ? "png" : "jpg"
  const image = `${base(url)}/${id}.${ext}`
  const page = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Screenshot</title><meta property="og:image" content="${image}"><meta name="twitter:card" content="summary_large_image">
<style>body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;background:#f6f7f2;font:14px system-ui;color:#5b6152}
img{max-width:min(96vw,1600px);max-height:86vh;border-radius:10px;box-shadow:0 8px 40px rgba(0,0,0,.15)}a{color:#2d4a19}</style></head>
<body><img src="${image}" alt="Screenshot"><div>Shared with <a href="${SITE}">Shotleaf</a> · gone in ${Math.max(1, Math.round(left / 60))} min · <a href="mailto:${REPORT}?subject=Report%20${id}">Report</a></div></body></html>`
  return new Response(page, { headers: { ...headers, "Content-Type": "text/html; charset=utf-8" } })
}

function kind(head) {
  if (head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4e && head[3] === 0x47) return "image/png"
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return "image/jpeg"
  return null
}

function randomID() {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
  return Array.from(crypto.getRandomValues(new Uint8Array(8)), (b) => abc[b % abc.length]).join("")
}

const json = (status, data) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } })
const notFound = () => new Response("This link has expired or never existed.", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8", "X-Robots-Tag": "noindex" } })
// https on the real domain (a custom domain may hand the Worker http), http only for local runs.
const base = (url) => (url.hostname === "localhost" || url.hostname === "127.0.0.1" ? url.origin : `https://${url.host}`)
