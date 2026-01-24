# Watching the Agent Play

You can connect a Factorio client to the test server and watch the agent control the game in real-time.

## Quick Start

1. **Start the test server** (if not already running):
   ```bash
   ./tests/setup.sh
   ```

2. **Launch Factorio** (the regular game, not headless)

3. **Connect to the server**:
   - From the main menu: **Multiplayer** → **Connect to address**
   - Enter: `localhost:34197`
   - Or from command line:
     ```bash
     # macOS Steam
     open -a Factorio --args --mp-connect localhost:34197
     ```

4. **Watch the action!**
   - You'll join as a spectator
   - The agent controls a character entity via RCON commands
   - You can see entities being created, resources being mined, etc.

## Server Configuration

The test server runs with these settings:
- **Game port**: 34197 (for client connections)
- **RCON port**: 27016 (for CLI commands)
- **No password** for game connections (local testing)
- **Allow commands**: enabled (for RCON)

## What You'll See

When the agent runs commands:

| Command | Visual Effect |
|---------|---------------|
| `character init` | Character spawns at (0,0) |
| `character teleport 10,10` | Character instantly moves |
| `place burner-mining-drill --at 5,5` | Drill appears on map |
| `mine --nearest rock-huge` | Rock disappears, items in inventory |
| `tick pause/resume` | Game freezes/unfreezes |

## Tips for Watching

### Follow the Character
1. Open the map (M key)
2. Find the character (should be near spawn)
3. Click to center view on it

### Use Console
Press ~ (tilde) to open the console and see:
- Command execution messages
- Entity creation/destruction
- Any Lua errors

### Slow Down Time
The agent can use:
```bash
factorioctl tick speed 0.5  # Half speed
factorioctl tick speed 0.1  # 10% speed - easy to watch
```

### Pause and Inspect
```bash
factorioctl tick pause
# Look around, inspect entities
factorioctl tick resume
```

## Multiplayer Notes

### You as a Player
If you join as a player (not spectator):
- You'll have your own character
- The agent's character is separate
- You can manually help or interfere (for testing)

### Force/Team
- Both you and the agent character are on `player` force
- Shared technology, shared vision
- Entities belong to whoever placed them

## Troubleshooting

### Can't Connect
```bash
# Check if server is running
./tests/cleanup.sh
./tests/setup.sh
```

### Character Not Visible
The agent's character is a separate entity. Look for it at spawn (0,0) or wherever it was teleported.

```bash
# Find character position
./target/release/factorioctl --port 27016 --password test_password character status
```

### Desync Issues
If the game desyncs:
1. Disconnect from server
2. Reconnect

### Server Log
Check server output:
```bash
tail -f logs/server.log
```

## Recording Gameplay

### macOS Screen Recording
- Cmd+Shift+5 to start recording
- Select the Factorio window

### OBS Studio
- Add Game Capture or Window Capture source
- Select Factorio window

### In-Game Demo Recording
```bash
# Via RCON (records server perspective)
./target/release/factorioctl --port 27016 --password test_password \
  execute "/c game.write_file('demo.dat', '', false)"
```

## Example Session

Terminal 1 - Server:
```bash
./tests/setup.sh
```

Terminal 2 - Agent commands:
```bash
CLI="./target/release/factorioctl --port 27016 --password test_password"

# Initialize
$CLI character init
$CLI tick speed 0.5  # Slow for watching

# Survey
$CLI get resources --area -100,-100,100,100

# Move to iron
$CLI character teleport 25,15

# Place a drill (if items available)
$CLI place burner-mining-drill --at 25,15 --direction south
```

Factorio Client:
- Connect to localhost:34197
- Watch character appear and move
- See drill get placed
