#!/usr/bin/env python3
"""APILA expiring screenshot links — one file, Python 3 standard library only.

POST /upload?ttl=SECONDS   (Authorization: Bearer <SHOTS_TOKEN>, body: PNG/JPEG)
    -> 201 {"url": "<SHOTS_PUBLIC_URL>/<id>", "expires": <unix time>}
GET  /<id>                 -> the image, until it expires; then 404
A sweep every minute deletes expired files.

Settings (environment):
    SHOTS_TOKEN       required; long random secret, the same one goes into APILA
    SHOTS_PUBLIC_URL  e.g. https://shot.example.com (what links start with)
    SHOTS_DIR         where images live (default ./data)
    SHOTS_PORT        default 8787; listens on 127.0.0.1 only (put the tunnel / proxy in front)
    SHOTS_MAX_MB      default 25
"""
import hmac
import json
import os
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = os.environ.get("SHOTS_TOKEN", "")
PUBLIC = os.environ.get("SHOTS_PUBLIC_URL", "").rstrip("/")
DATA = os.path.abspath(os.environ.get("SHOTS_DIR", "data"))
PORT = int(os.environ.get("SHOTS_PORT", "8787"))
MAX_BYTES = int(os.environ.get("SHOTS_MAX_MB", "25")) * 1024 * 1024
MAX_TTL = 7 * 24 * 3600
ID = re.compile(r"^[A-Za-z0-9_-]{8,32}$")
TYPES = {b"\x89PNG": ("png", "image/png"), b"\xff\xd8\xff": ("jpg", "image/jpeg")}


def kind(head):
    return next((t for magic, t in TYPES.items() if head.startswith(magic)), None)


def paths(shot_id):
    return os.path.join(DATA, shot_id + ".bin"), os.path.join(DATA, shot_id + ".json")


def sweep():
    now = time.time()
    for name in os.listdir(DATA):
        if not name.endswith(".json"):
            continue
        meta_path = os.path.join(DATA, name)
        try:
            with open(meta_path) as f:
                expired = json.load(f)["expires"] <= now
        except (OSError, ValueError, KeyError):
            expired = True
        if expired:
            for p in paths(name[:-5]):
                try:
                    os.remove(p)
                except OSError:
                    pass


def sweeper():
    while True:
        try:
            sweep()
        except OSError:
            pass
        time.sleep(60)


class Handler(BaseHTTPRequestHandler):
    server_version = "apila-shots"

    def send(self, code, body=b"", content_type="application/json", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def error(self, code, message):
        self.send(code, json.dumps({"error": message}).encode())

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/upload":
            return self.error(404, "not found")
        given = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        if not TOKEN or not hmac.compare_digest(given.encode(), TOKEN.encode()):
            return self.error(401, "wrong token")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            ttl = int(parse_qs(url.query).get("ttl", ["3600"])[0])
        except ValueError:
            return self.error(400, "bad request")
        if not 0 < length <= MAX_BYTES:
            return self.error(413, "too big")
        if not 60 <= ttl <= MAX_TTL:
            return self.error(400, "ttl must be 60…604800 seconds")
        body = self.rfile.read(length)
        found = kind(body[:4])
        if not found:
            return self.error(415, "only PNG and JPEG")
        shot_id = secrets.token_urlsafe(9)  # 12 characters, unguessable
        image_path, meta_path = paths(shot_id)
        expires = int(time.time()) + ttl
        with open(image_path, "wb") as f:
            f.write(body)
        with open(meta_path, "w") as f:
            json.dump({"expires": expires, "type": found[1]}, f)
        base = PUBLIC or f"http://{self.headers.get('Host', 'localhost')}"
        self.send(201, json.dumps({"url": f"{base}/{shot_id}", "expires": expires}).encode())

    def do_GET(self):
        shot_id = urlparse(self.path).path.strip("/").removesuffix(".png").removesuffix(".jpg")
        if not ID.match(shot_id):
            return self.error(404, "not found")
        image_path, meta_path = paths(shot_id)
        try:
            with open(meta_path) as f:
                meta = json.load(f)
            if meta["expires"] <= time.time():
                return self.error(404, "expired")
            with open(image_path, "rb") as f:
                body = f.read()
        except (OSError, ValueError, KeyError):
            return self.error(404, "not found")
        left = int(meta["expires"] - time.time())
        self.send(200, body, meta.get("type", "image/png"), {
            "Cache-Control": f"private, max-age={min(left, 300)}",
            "Content-Disposition": f'inline; filename="screenshot-{shot_id}.{"jpg" if "jpeg" in meta.get("type", "") else "png"}"',
            "X-Robots-Tag": "noindex",
        })

    do_HEAD = do_GET

    def log_message(self, fmt, *args):  # one short line per request, no IPs kept
        print(f"{self.command} {self.path.split('?')[0]} {args[1] if len(args) > 1 else ''}", flush=True)


def main():
    if not TOKEN:
        raise SystemExit("Set SHOTS_TOKEN (e.g. `openssl rand -hex 24`).")
    os.makedirs(DATA, exist_ok=True)
    threading.Thread(target=sweeper, daemon=True).start()
    print(f"apila-shots on 127.0.0.1:{PORT}, files in {DATA}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
