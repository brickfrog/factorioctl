import struct
import unittest
from unittest import mock

import rcon


def packet(req_id: int, packet_type: int, body: str) -> bytes:
    body_bytes = body.encode("utf-8")
    size = 4 + 4 + len(body_bytes) + 1 + 1
    return struct.pack("<iii", size, req_id, packet_type) + body_bytes + b"\x00\x00"


class FakeSocket:
    def __init__(self, recv_data: bytes = b"", connect_error: OSError | None = None):
        self.recv_data = bytearray(recv_data)
        self.connect_error = connect_error
        self.closed = False
        self.sent: list[bytes] = []
        self.timeout = None

    def settimeout(self, timeout):
        self.timeout = timeout

    def connect(self, _addr):
        if self.connect_error:
            raise self.connect_error

    def sendall(self, data: bytes):
        self.sent.append(data)

    def recv(self, n: int) -> bytes:
        if not self.recv_data:
            return b""
        chunk = bytes(self.recv_data[:n])
        del self.recv_data[:n]
        return chunk

    def close(self):
        self.closed = True


class RCONReconnectTests(unittest.TestCase):
    def test_execute_reconnects_and_retries_after_dropped_socket(self):
        first = FakeSocket(packet(1, 2, ""))
        second = FakeSocket(packet(3, 2, "") + packet(4, 2, "ok"))
        sockets = [first, second]

        def socket_factory(*_args, **_kwargs):
            return sockets.pop(0)

        with mock.patch("rcon.socket.socket", side_effect=socket_factory):
            with mock.patch("rcon.time.sleep", lambda _delay: None):
                client = rcon.RCONClient("localhost", 27015, "pw")
                self.assertEqual(client.execute("/silent-command rcon.print('ok')"), "ok")

        self.assertTrue(first.closed)
        self.assertGreaterEqual(len(first.sent), 2)
        self.assertGreaterEqual(len(second.sent), 2)

    def test_initial_connect_retries_until_factorio_is_available(self):
        first = FakeSocket(connect_error=ConnectionRefusedError("no server"))
        second = FakeSocket(packet(2, 2, ""))
        sockets = [first, second]

        def socket_factory(*_args, **_kwargs):
            return sockets.pop(0)

        with mock.patch("rcon.socket.socket", side_effect=socket_factory):
            with mock.patch("rcon.time.sleep", lambda _delay: None):
                client = rcon.RCONClient("localhost", 27015, "pw")

        self.assertIs(client.sock, second)
        self.assertTrue(first.closed)


if __name__ == "__main__":
    unittest.main()
