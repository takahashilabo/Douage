#!/usr/bin/env python3
"""
HTTPS server for Godot WebXR development (Douage - 胴上げ体験VR).
Requires cert.pem and key.pem in this directory (generated via mkcert).

Setup (one-time):
  brew install mkcert
  cd server
  mkcert -key-file key.pem -cert-file cert.pem <LAN_IP> localhost 127.0.0.1

Run:
  cd Douage
  python3 server/serve.py

Access from Quest 3: https://<LAN_IP>:8070/
"""
import http.server
import ssl
import os
import socket

SERVE_DIR = os.path.join(os.path.dirname(__file__), "..", "build", "web")
PORT = 8070


class XRHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.abspath(SERVE_DIR), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")


cert = os.path.join(os.path.dirname(__file__), "cert.pem")
key = os.path.join(os.path.dirname(__file__), "key.pem")

if not os.path.exists(cert) or not os.path.exists(key):
    print("ERROR: cert.pem / key.pem not found in server/")
    print("Run the mkcert setup steps described in this file's header.")
    raise SystemExit(1)

httpd = http.server.HTTPServer(("0.0.0.0", PORT), XRHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

local_ip = socket.gethostbyname(socket.gethostname())
print(f"Serving at https://{local_ip}:{PORT}/")
httpd.serve_forever()
