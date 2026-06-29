"""Source RCON protocol client for Factorio and Lua string encoding."""

import socket
import struct
import time
from typing import Any


class RCONClient:
    """Minimal Source RCON protocol client for Factorio."""

    SERVERDATA_AUTH = 3
    SERVERDATA_EXECCOMMAND = 2

    def __init__(
        self,
        host: str,
        port: int,
        password: str,
        *,
        timeout: float = 30.0,
        reconnect_initial_delay: float = 0.5,
        reconnect_max_delay: float = 10.0,
        retry_forever: bool = True,
        log: Any = None,
    ):
        self.host = host
        self.port = port
        self.password = password
        self.timeout = timeout
        self.reconnect_initial_delay = reconnect_initial_delay
        self.reconnect_max_delay = reconnect_max_delay
        self.retry_forever = retry_forever
        self.log = log
        self._request_id = 0
        self.sock = None
        self._connect_with_retry("initial connect")

    def _log(self, level: str, message: str, *args):
        if not self.log:
            return
        method = getattr(self.log, level, None)
        if method:
            method(message, *args)

    def _close_socket(self):
        sock = self.sock
        self.sock = None
        if sock:
            try:
                sock.close()
            except OSError:
                pass

    def _connect_once(self):
        self._close_socket()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect((self.host, self.port))
            self.sock = sock
            self._authenticate()
        except Exception:
            try:
                sock.close()
            except OSError:
                pass
            self.sock = None
            raise

    def _connect_with_retry(self, reason: str):
        delay = max(0.0, self.reconnect_initial_delay)
        max_delay = max(delay, self.reconnect_max_delay)
        attempt = 0
        while True:
            attempt += 1
            try:
                self._connect_once()
                if attempt > 1:
                    self._log(
                        "info",
                        "RCON reconnected to {}:{} after {} attempt(s)",
                        self.host,
                        self.port,
                        attempt,
                    )
                return
            except (ConnectionError, socket.timeout, OSError) as e:
                self._close_socket()
                if not self.retry_forever:
                    raise
                if attempt == 1:
                    self._log(
                        "warning",
                        "RCON unavailable during {}; retrying until Factorio returns: {}",
                        reason,
                        e,
                    )
                else:
                    self._log(
                        "debug",
                        "RCON reconnect attempt {} failed during {}: {}",
                        attempt,
                        reason,
                        e,
                    )
                if delay > 0:
                    time.sleep(delay)
                    delay = min(max_delay, delay * 2 if delay else max_delay)

    def _next_id(self) -> int:
        self._request_id += 1
        return self._request_id

    def _send_packet(self, packet_type: int, body: str) -> int:
        if self.sock is None:
            raise ConnectionError("RCON socket is not connected")
        req_id = self._next_id()
        body_bytes = body.encode("utf-8")
        size = 4 + 4 + len(body_bytes) + 1 + 1
        packet = struct.pack("<iii", size, req_id, packet_type) + body_bytes + b"\x00\x00"
        self.sock.sendall(packet)
        return req_id

    def _recv_packet(self) -> tuple[int, int, str]:
        raw = self._recv_bytes(4)
        (size,) = struct.unpack("<i", raw)
        data = self._recv_bytes(size)
        req_id = struct.unpack("<i", data[0:4])[0]
        pkt_type = struct.unpack("<i", data[4:8])[0]
        body = data[8:-2].decode("utf-8", errors="replace")
        return req_id, pkt_type, body

    def _recv_bytes(self, n: int) -> bytes:
        if self.sock is None:
            raise ConnectionError("RCON socket is not connected")
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("RCON connection closed")
            buf += chunk
        return buf

    def _authenticate(self):
        self._send_packet(self.SERVERDATA_AUTH, self.password)
        # Factorio sends a single auth response (not two like Source engine)
        req_id, _, _ = self._recv_packet()
        if req_id == -1:
            raise ConnectionError("RCON authentication failed")

    def execute(self, command: str) -> str:
        while True:
            try:
                if self.sock is None:
                    self._connect_with_retry("command")
                self._send_packet(self.SERVERDATA_EXECCOMMAND, command)
                _, _, body = self._recv_packet()
                return body
            except (ConnectionError, socket.timeout, OSError) as e:
                self._log(
                    "warning",
                    "RCON command failed; reconnecting before retry: {}",
                    e,
                )
                self._close_socket()
                self._connect_with_retry("command retry")

    def close(self):
        self._close_socket()


class ThreadSafeRCON:
    """Thread-safe wrapper around RCONClient. Duck-type compatible."""

    def __init__(self, rcon: RCONClient, lock=None):
        import threading
        self._rcon = rcon
        self._lock = lock or threading.Lock()

    def execute(self, command: str) -> str:
        with self._lock:
            return self._rcon.execute(command)

    def close(self):
        self._rcon.close()


def lua_long_string(text: str) -> str:
    """Wrap text in a Lua long bracket string with auto-detected level."""
    level = 0
    while f']{"=" * level}]' in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[{text}]{eq}]"
