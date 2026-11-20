#!/usr/bin/env python3
"""Loopback-only reverse proxy for ADN MyCarWash kiosk.
The kiosk secret never enters Chromium, URL, JS, or localStorage.
"""
import http.server
import os
import ssl
import urllib.parse
import urllib.request
import urllib.error
import pathlib
import re
import sys

PUBLIC = 'https://mycarwash.adnpublicidad.site'
API_ROOT = '/api/index.php/api/v1/kiosk/rpi01c/'
ALLOWED_API = re.compile(r'^/api/index\.php/api/v1/kiosk/rpi01c/(?:bootstrap|monitor|logo|photos/[0-9]+)$')
STATIC = re.compile(r'^/(?:index\.html|flutter\.js|flutter_bootstrap\.js|main\.dart\.js|manifest\.json|favicon\.png|version\.json|canvaskit/[a-zA-Z0-9_./-]+|assets/[a-zA-Z0-9_./@-]+|icons/[a-zA-Z0-9_./-]+)$')
KEY_FILE = pathlib.Path.home() / '.local/share/adn-mycarwash-kiosk/device.key'

class Proxy(http.server.BaseHTTPRequestHandler):
    server_version = 'MCWKiosk/1.0'
    def log_message(self, format, *args):
        # Never log device credentials or authorization headers.
        sys.stderr.write('%s %s\n' % (self.log_date_time_string(), (format % args)[:250]))

    def do_POST(self):
        self.send_error(405)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path in ('/', '/index.html'):
            target = PUBLIC + '/index.html'
            is_api = False
        elif ALLOWED_API.fullmatch(path):
            target = PUBLIC + path
            is_api = True
        elif STATIC.fullmatch(path) and '..' not in path:
            target = PUBLIC + path
            is_api = False
        else:
            self.send_error(404)
            return

        if is_api:
            try:
                secret = KEY_FILE.read_text(encoding='ascii').strip()
            except OSError:
                self.send_error(503, 'Pantalla sin vincular')
                return
            if re.fullmatch('[a-f0-9]{64}', secret) is None:
                self.send_error(503, 'Clave del dispositivo inválida')
                return
            headers = {'Accept': 'application/json, image/*', 'X-MCW-Kiosk-Key': secret}
        else:
            headers = {'Accept': '*/*'}
        try:
            req = urllib.request.Request(target, headers=headers, method='GET')
            # Refuse redirects to arbitrary hosts.
            with urllib.request.urlopen(req, timeout=20) as upstream:
                final = urllib.parse.urlsplit(upstream.url)
                if final.scheme != 'https' or final.netloc != 'mycarwash.adnpublicidad.site':
                    self.send_error(502, 'Redirección inesperada')
                    return
                content_type = upstream.headers.get('Content-Type', 'application/octet-stream')
                body = upstream.read(24 * 1024 * 1024 + 1)
                if len(body) > 24 * 1024 * 1024:
                    self.send_error(502, 'Archivo demasiado grande')
                    return
                self.send_response(200)
                self.send_header('Content-Type', content_type)
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Cache-Control', 'no-store' if is_api or path in ('/', '/index.html') else 'public, max-age=300')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(b'Error de respuesta del servidor de monitoreo')
        except Exception:
            if path in ('/', '/index.html'):
                page = b'<!doctype html><html><meta charset="utf-8"><meta http-equiv="refresh" content="10"><body style="background:#101b20;color:white;font-family:sans-serif;text-align:center;margin-top:20vh"><h2>Reconectando ADN MyCarWash...</h2></body></html>'
                self.send_response(503)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(page)))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write(page)
            else:
                self.send_error(502, 'No se pudo contactar Hostinger')

if __name__ == '__main__':
    # No LAN listener; only the local Chromium process may call the proxy.
    http.server.ThreadingHTTPServer(('127.0.0.1', 8787), Proxy).serve_forever()
