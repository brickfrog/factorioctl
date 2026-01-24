# RCON Protocol Reference

Factorio uses the Source RCON protocol for remote server administration.

## Protocol Overview

RCON is a TCP-based protocol. All integers are little-endian.

### Packet Format

```
+---------------+---------------+---------------+---------------+
|      Size     |   Request ID  |     Type      |     Body      |
|   (4 bytes)   |   (4 bytes)   |   (4 bytes)   | (variable)    |
+---------------+---------------+---------------+---------------+
                                                 |   Null (1B)   |
                                                 +---------------+
```

- **Size**: Length of packet body + 10 (does not include size field itself)
- **Request ID**: Client-chosen ID echoed in response
- **Type**: Packet type (see below)
- **Body**: Null-terminated ASCII string
- **Terminator**: Additional null byte after body

### Packet Types

| Type | Name | Direction | Description |
|------|------|-----------|-------------|
| 3 | SERVERDATA_AUTH | Client → Server | Authentication request (body = password) |
| 2 | SERVERDATA_AUTH_RESPONSE | Server → Client | Authentication response |
| 2 | SERVERDATA_EXECCOMMAND | Client → Server | Command execution request |
| 0 | SERVERDATA_RESPONSE_VALUE | Server → Client | Command response |

Note: Type 2 is used for both AUTH_RESPONSE and EXECCOMMAND.

### Authentication Flow

1. Client sends SERVERDATA_AUTH packet with password as body
2. Server responds with SERVERDATA_AUTH_RESPONSE
   - Success: Response ID matches request ID
   - Failure: Response ID is -1

### Command Execution Flow

1. Client sends SERVERDATA_EXECCOMMAND with command as body
2. Server responds with SERVERDATA_RESPONSE_VALUE containing output

## Python Implementation

See `scripts/rcon_client.py` for a working implementation.

### Encoding a Packet

```python
import struct

def encode_packet(request_id: int, packet_type: int, body: str) -> bytes:
    body_bytes = body.encode("utf-8") + b"\x00"
    size = 4 + 4 + len(body_bytes) + 1
    return struct.pack("<iii", size, request_id, packet_type) + body_bytes + b"\x00"
```

### Decoding a Packet

```python
def decode_packet(data: bytes) -> tuple[int, int, str]:
    size, request_id, packet_type = struct.unpack("<iii", data[:12])
    body = data[12:-2].decode("utf-8")
    return request_id, packet_type, body
```

## Factorio-Specific Notes

### Command Format

- Console commands start with `/c` or `/silent-command`
- Commands execute Lua code in the game context

```
/c rcon.print(game.tick)
/c game.surfaces[1].create_entity{name='iron-chest', position={0,0}}
/silent-command game.speed = 2  -- No console output
```

### Output via rcon.print()

Use `rcon.print()` to send data back to the RCON client:

```lua
/c rcon.print("Hello from server!")
/c rcon.print(tostring(game.tick))
/c local count = #game.players; rcon.print("Players: " .. count)
```

### Warmup Command

The first command after connection may not produce output. Send a dummy command:

```python
client.execute("/c")  # Warmup
response = client.execute("/c rcon.print('test')")  # Now works
```

### Response Handling

- Empty responses are valid (command produced no output)
- Responses may contain newlines
- Error messages are returned as response body

## Testing RCON

```bash
# Using the Python client
python scripts/rcon_client.py --port 27015 --password test

# Interactive mode
> /c rcon.print('hello')
hello
> /c rcon.print(game.tick)
1234
```

## References

- [Source RCON Protocol](https://developer.valvesoftware.com/wiki/Source_RCON_Protocol)
- [Factorio API - LuaRCON](https://lua-api.factorio.com/latest/classes/LuaRCON.html)
