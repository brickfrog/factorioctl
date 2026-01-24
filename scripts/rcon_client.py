#!/usr/bin/env python3
"""
Simple RCON client for Factorio using the Source RCON protocol.

Usage:
    python scripts/rcon_client.py --port 27015 --password test "/c rcon.print(game.tick)"

The Source RCON protocol is a TCP-based protocol used by many game servers.
See: https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
"""

import argparse
import socket
import struct
import sys
from dataclasses import dataclass
from typing import Optional

# RCON packet types
SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


@dataclass
class RconPacket:
    """Represents an RCON packet."""
    request_id: int
    packet_type: int
    body: str

    def encode(self) -> bytes:
        """Encode packet to bytes for sending over the wire."""
        body_bytes = self.body.encode("utf-8") + b"\x00"
        # Packet: size (4) + request_id (4) + type (4) + body + null terminator
        size = 4 + 4 + len(body_bytes) + 1
        return struct.pack("<iii", size, self.request_id, self.packet_type) + body_bytes + b"\x00"

    @classmethod
    def decode(cls, data: bytes) -> "RconPacket":
        """Decode bytes received from the wire into a packet."""
        size, request_id, packet_type = struct.unpack("<iii", data[:12])
        # Body is everything after the header minus the two null terminators
        body = data[12:-2].decode("utf-8", errors="replace")
        return cls(request_id=request_id, packet_type=packet_type, body=body)


class RconClient:
    """Simple RCON client for Factorio."""

    def __init__(self, host: str = "localhost", port: int = 27015, password: str = ""):
        self.host = host
        self.port = port
        self.password = password
        self.socket: Optional[socket.socket] = None
        self.request_id = 0

    def connect(self) -> bool:
        """Connect and authenticate with the RCON server."""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.settimeout(10.0)
        self.socket.connect((self.host, self.port))

        # Authenticate
        auth_packet = RconPacket(
            request_id=self._next_id(),
            packet_type=SERVERDATA_AUTH,
            body=self.password
        )
        self._send(auth_packet)

        # Read auth response
        response = self._receive()
        if response is None or response.request_id == -1:
            return False

        return True

    def execute(self, command: str) -> str:
        """Execute a command and return the response."""
        if self.socket is None:
            raise RuntimeError("Not connected")

        packet = RconPacket(
            request_id=self._next_id(),
            packet_type=SERVERDATA_EXECCOMMAND,
            body=command
        )
        self._send(packet)

        response = self._receive()
        if response is None:
            return ""

        return response.body

    def close(self):
        """Close the connection."""
        if self.socket:
            self.socket.close()
            self.socket = None

    def _next_id(self) -> int:
        """Generate the next request ID."""
        self.request_id += 1
        return self.request_id

    def _send(self, packet: RconPacket):
        """Send a packet to the server."""
        if self.socket is None:
            raise RuntimeError("Not connected")
        self.socket.sendall(packet.encode())

    def _receive(self) -> Optional[RconPacket]:
        """Receive a packet from the server."""
        if self.socket is None:
            raise RuntimeError("Not connected")

        # Read size first (4 bytes)
        size_data = self._recv_exact(4)
        if not size_data:
            return None

        size = struct.unpack("<i", size_data)[0]

        # Read the rest of the packet
        data = self._recv_exact(size)
        if not data:
            return None

        return RconPacket.decode(size_data + data)

    def _recv_exact(self, n: int) -> bytes:
        """Receive exactly n bytes."""
        if self.socket is None:
            raise RuntimeError("Not connected")

        data = b""
        while len(data) < n:
            chunk = self.socket.recv(n - len(data))
            if not chunk:
                return b""
            data += chunk
        return data


def main():
    parser = argparse.ArgumentParser(description="Factorio RCON client")
    parser.add_argument(
        "--host", "-H",
        default="localhost",
        help="RCON server host (default: localhost)"
    )
    parser.add_argument(
        "--port", "-p",
        type=int,
        default=27015,
        help="RCON server port (default: 27015)"
    )
    parser.add_argument(
        "--password", "-P",
        default="",
        help="RCON password"
    )
    parser.add_argument(
        "command",
        nargs="?",
        help="Command to execute (interactive mode if not provided)"
    )

    args = parser.parse_args()

    client = RconClient(args.host, args.port, args.password)

    try:
        print(f"Connecting to {args.host}:{args.port}...")
        if not client.connect():
            print("Authentication failed!", file=sys.stderr)
            return 1
        print("Connected and authenticated.")

        if args.command:
            # Single command mode
            response = client.execute(args.command)
            if response:
                print(response)
        else:
            # Interactive mode
            print("Interactive mode. Type 'quit' or 'exit' to quit.")
            while True:
                try:
                    command = input("> ").strip()
                    if command.lower() in ("quit", "exit"):
                        break
                    if not command:
                        continue
                    response = client.execute(command)
                    if response:
                        print(response)
                except EOFError:
                    break

        return 0

    except ConnectionRefusedError:
        print(f"Connection refused to {args.host}:{args.port}", file=sys.stderr)
        return 1
    except socket.timeout:
        print("Connection timed out", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
