#!/usr/bin/env python3
"""Small authenticated static server for generated Tran reports."""
from __future__ import annotations

import base64
import hashlib
import hmac
import http.server
import os
from functools import partial
from pathlib import Path


class AuthenticatedStaticHandler(http.server.SimpleHTTPRequestHandler):
    server_version = "SteveTradingReports/1.0"

    def _authorized(self) -> bool:
        expected_user = os.environ.get("REPORTS_USER", "stevetrading")
        expected_hash = os.environ.get("REPORTS_PASSWORD_SHA256", "")
        if not expected_hash:
            return True

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Basic "):
            return False

        try:
            decoded = base64.b64decode(auth[6:], validate=True).decode("utf-8")
            user, password = decoded.split(":", 1)
        except Exception:
            return False

        got_hash = hashlib.sha256(password.encode("utf-8")).hexdigest()
        return (
            hmac.compare_digest(user, expected_user)
            and hmac.compare_digest(got_hash, expected_hash)
        )

    def do_HEAD(self) -> None:
        if not self._authorized():
            self._reject()
            return
        super().do_HEAD()

    def do_GET(self) -> None:
        if not self._authorized():
            self._reject()
            return
        super().do_GET()

    def _reject(self) -> None:
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="Tran Reports"')
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"authentication required\n")


def main() -> None:
    host = os.environ.get("REPORTS_HOST", "0.0.0.0")
    port = int(os.environ.get("REPORTS_PORT", "8080"))
    root = Path(
        os.environ.get(
            "REPORTS_ROOT",
            "/opt/stevetrading/shared/Data-Preprocessor/report-viewer/public",
        )
    )
    root.mkdir(parents=True, exist_ok=True)

    handler = partial(AuthenticatedStaticHandler, directory=str(root))
    with http.server.ThreadingHTTPServer((host, port), handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
