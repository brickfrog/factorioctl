# Factorio CLI Reference

This document covers useful Factorio command-line options for headless server operation.

## Installation Location

On macOS with Steam:
```
/Users/mark/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio
```

Data files (configs, API docs):
```
/Users/mark/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/data/
```

## Creating Maps

```bash
# Create a new map with default settings
factorio --create save.zip

# Create with custom map generation settings
factorio --create save.zip --map-gen-settings map-gen.json

# Specify map settings (difficulty, pollution, etc.)
factorio --create save.zip --map-settings map-settings.json

# Use a preset (rich-resources, marathon, death-world, rail-world, ribbon-world, island)
factorio --create save.zip --preset rail-world

# Specify seed for reproducibility
factorio --create save.zip --map-gen-seed 12345
```

## Running a Headless Server

```bash
# Basic server
factorio --start-server save.zip

# With RCON enabled
factorio --start-server save.zip \
  --rcon-port 27015 \
  --rcon-password mypassword

# With custom server settings
factorio --start-server save.zip \
  --server-settings server-settings.json \
  --rcon-port 27015 \
  --rcon-password mypassword

# Bind RCON to specific interface
factorio --start-server save.zip \
  --rcon-bind 127.0.0.1:27015 \
  --rcon-password mypassword
```

## Server Settings (test-server.json)

Key settings for testing:

```json
{
  "name": "Test Server",
  "auto_pause": false,           // Don't pause when no players
  "visibility": {"public": false, "lan": false},
  "require_user_verification": false,
  "allow_commands": "true",      // Allow console commands
  "autosave_interval": 0         // Disable autosave
}
```

## Map Generation Settings (test-map-gen.json)

Key settings for testing:

```json
{
  "peaceful_mode": true,
  "autoplace_controls": {
    "enemy-base": {"frequency": 0, "size": 0}  // No enemies
  },
  "seed": 12345  // Fixed seed for reproducibility
}
```

## Useful CLI Options

| Option | Description |
|--------|-------------|
| `--create FILE` | Create a new map |
| `--start-server FILE` | Start headless server |
| `--rcon-port N` | RCON port number |
| `--rcon-password PWD` | RCON password |
| `--server-settings FILE` | Server configuration |
| `--map-gen-settings FILE` | Map generation settings |
| `--map-settings FILE` | Map settings (pollution, etc.) |
| `--preset NAME` | Use built-in preset |
| `--benchmark FILE` | Benchmark a save file |
| `--until-tick N` | Run until specific tick |

## Example Session

```bash
# 1. Create a peaceful test map
factorio --create test.zip \
  --map-gen-settings configs/test-map-gen.json

# 2. Start the server
factorio --start-server test.zip \
  --rcon-port 27015 \
  --rcon-password test \
  --server-settings configs/test-server.json

# 3. The server will output logs showing RCON is ready:
# "Starting RCON interface at IP ADDR:({0.0.0.0:27015})"
```
