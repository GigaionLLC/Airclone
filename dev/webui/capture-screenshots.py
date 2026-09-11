"""Screenshot the Airclone Web UI with headless Chrome over CDP.

Native-window capture is not possible from this session, but the Web UI is a web
page, so headless Chrome can capture it properly. There is no websocket library
available, so this speaks the protocol directly -- it is a short, well-specified
frame format and only needs text frames.

Auth is real: it signs in over HTTP with `requests`, takes the session cookie
Chrome would have got, and installs it with Network.setCookie. Nothing about the
server is weakened to take a picture.
"""

import base64
import json
import os
import socket
import struct
import subprocess
import sys
import time
from urllib.parse import urlparse

import requests

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
ORIGIN = "http://127.0.0.1:5799"
PORT = 9333


class Ws:
    """The smallest websocket client that can carry CDP."""

    def __init__(self, url):
        u = urlparse(url)
        self.sock = socket.create_connection((u.hostname, u.port), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        path = u.path + (("?" + u.query) if u.query else "")
        req = (
            f"GET {path} HTTP/1.1\r\nHost: {u.hostname}:{u.port}\r\n"
            f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.sock.recv(4096)
        assert b"101" in buf.split(b"\r\n")[0], buf[:200]
        self.buf = buf.split(b"\r\n\r\n", 1)[1]
        self.next_id = 0

    def _recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, method, **params):
        self.next_id += 1
        payload = json.dumps(
            {"id": self.next_id, "method": method, "params": params}
        ).encode()
        # Client frames must be masked. FIN + text opcode.
        header = b"\x81"
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += b"\xfe" + struct.pack(">H", n)
        else:
            header += b"\xff" + struct.pack(">Q", n)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)
        return self.next_id

    def _frame(self):
        b0, b1 = self._recv(2)
        length = b1 & 0x7F
        if length == 126:
            length = struct.unpack(">H", self._recv(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", self._recv(8))[0]
        if b1 & 0x80:  # server frames are not normally masked
            mask = self._recv(4)
            data = self._recv(length)
            data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
        else:
            data = self._recv(length)
        return b0 & 0x0F, (b0 & 0x80) != 0, data

    def result(self, want_id, timeout=60):
        deadline = time.time() + timeout
        pending = b""
        while time.time() < deadline:
            opcode, fin, data = self._frame()
            if opcode == 0x8:
                raise EOFError("closed by peer")
            if opcode in (0x1, 0x0):
                pending += data
                if not fin:
                    continue
                msg = json.loads(pending.decode())
                pending = b""
                if msg.get("id") == want_id:
                    if "error" in msg:
                        raise RuntimeError(msg["error"])
                    return msg.get("result", {})
        raise TimeoutError(f"no reply to id {want_id}")

    def call(self, method, **params):
        return self.result(self.send(method, **params))


def session_cookie(user, password):
    """Sign in the way a browser does, and return the session token."""
    r = requests.post(
        f"{ORIGIN}/api/login",
        json={"username": user, "password": password},
        headers={"X-Airclone-WebUI": "1"},
        timeout=20,
    )
    r.raise_for_status()
    for name, value in r.cookies.items():
        if name == "airclone_webui_session":
            return value
    raise SystemExit("no session cookie returned")


def main():
    user, password, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(outdir, exist_ok=True)
    token = session_cookie(user, password)
    print("signed in")

    profile = os.path.join(outdir, "_chrome-profile")
    proc = subprocess.Popen(
        [
            CHROME,
            "--headless=new",
            f"--remote-debugging-port={PORT}",
            f"--user-data-dir={profile}",
            "--no-first-run",
            "--no-default-browser-check",
            "--hide-scrollbars",
            "--force-device-scale-factor=2",
            "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        ws_url = None
        for _ in range(60):
            try:
                tabs = requests.get(
                    f"http://127.0.0.1:{PORT}/json/list", timeout=2
                ).json()
                page = [t for t in tabs if t.get("type") == "page"]
                if page:
                    ws_url = page[0]["webSocketDebuggerUrl"]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        if not ws_url:
            raise SystemExit("Chrome never exposed a debugging target")

        ws = Ws(ws_url)
        ws.call("Page.enable")
        ws.call("Network.enable")
        ws.call(
            "Network.setCookie",
            name="airclone_webui_session",
            value=token,
            domain="127.0.0.1",
            path="/",
            httpOnly=True,
        )

        shots = [
            ("webui-login.png", f"{ORIGIN}/login", 1100, 760, False),
            ("webui-desktop.png", f"{ORIGIN}/", 1440, 900, False),
            ("webui-phone.png", f"{ORIGIN}/", 390, 844, True),
        ]
        for name, url, w, h, mobile in shots:
            ws.call(
                "Emulation.setDeviceMetricsOverride",
                width=w,
                height=h,
                deviceScaleFactor=2,
                mobile=mobile,
            )
            ws.call("Page.navigate", url=url)
            # CanvasKit needs a moment after load to paint the first frame.
            time.sleep(9)
            res = ws.call("Page.captureScreenshot", format="png")
            path = os.path.join(outdir, name)
            with open(path, "wb") as f:
                f.write(base64.b64decode(res["data"]))
            print(f"{name}: {os.path.getsize(path)} bytes ({w}x{h})")
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
