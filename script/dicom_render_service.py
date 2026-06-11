#!/usr/bin/env python3
# Tiny internal HTTP service that renders SIDEXIS DICOMs to PNG with window/level on demand.
# Ivory's Rails app proxies to it (Rails holds the auth); this service is localhost/bridge-only.
# Stdlib only (no Flask) so the venv stays minimal. Read-only on the archive.
import os, io, json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from render_dicom import render

ARCHIVE = os.environ.get("SIDEXIS_ARCHIVE_ROOT", "/var/lib/docker/_sidexis_archive")
PORT = int(os.environ.get("DICOM_RENDER_PORT", "8810"))


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass  # quiet

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/health":
            self._send(200, b"ok", "text/plain"); return
        if u.path != "/render":
            self._send(404, b"not found", "text/plain"); return
        q = parse_qs(u.query)
        rel = (q.get("path", [""])[0]).lstrip("/")
        path = os.path.realpath(os.path.join(ARCHIVE, rel))
        if not path.startswith(os.path.realpath(ARCHIVE) + os.sep) or not os.path.isfile(path) or not path.lower().endswith(".dcm"):
            self._send(404, b"not a dicom", "text/plain"); return
        wc = q.get("wc", [None])[0]
        ww = q.get("ww", [None])[0]
        inv = q.get("invert", ["0"])[0] in ("1", "true")
        try:
            png, rwc, rww, size = render(path, float(wc) if wc else None, float(ww) if ww else None, invert=inv)
        except Exception as e:
            self._send(500, json.dumps({"error": str(e)}).encode(), "application/json"); return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(png)))
        self.send_header("X-Window-Center", str(rwc))
        self.send_header("X-Window-Width", str(rww))
        self.send_header("Cache-Control", "private, max-age=3600")
        self.end_headers()
        self.wfile.write(png)

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    print(f"dicom render service on :{PORT}, archive={ARCHIVE}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
