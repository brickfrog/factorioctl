# Factorioctl

A CLI tool and MCP server for controlling Factorio via RCON. Enables both human operators and LLM agents to interact with Factorio programmatically.

## Quick Start

```bash
# Set up connection (or use environment variables)
export FACTORIO_RCON_HOST=localhost
export FACTORIO_RCON_PORT=27015
export FACTORIO_RCON_PASSWORD=yourpassword

# Or use the config command
factorioctl config set --host localhost --port 27015 --password yourpassword

# Check connection
factorioctl character status
```

## CLI Commands

### High-Level Commands (Recommended)

These commands handle pathfinding, walking, and complex operations automatically:

```bash
# Route belts from A to B with automatic pathfinding
factorioctl belt line --from 0,0 --to 10,0 --belt transport-belt

# Build drill arrays on resource patches
factorioctl build drill-array --count 4 --resource iron-ore --near 50,-30

# Build smelter lines
factorioctl build smelter-line --count 4 --at 45,-30 --furnace-type stone-furnace

# Run power lines between points
factorioctl power line --from 0,0 --to 20,0 --pole small-electric-pole

# Walk to a position with pathfinding
factorioctl walk-to --to 50,-30

# Gather resources (walk and mine)
factorioctl gather --resource iron-ore --count 10
```

### Query Commands

```bash
# Get entities in an area
factorioctl get entities --area 0,0,100,100

# Get resources
factorioctl get resources --area 0,0,100,100 --type iron-ore

# Get character status and inventory
factorioctl character status
factorioctl character inventory

# Get game tick
factorioctl get tick
```

### Low-Level Commands

```bash
# Place a single entity
factorioctl place --entity transport-belt --at 5,5 --direction east

# Mine at a position
factorioctl mine --at 5,5

# Remove an entity
factorioctl remove --unit-number 123

# Execute raw Lua
factorioctl exec "rcon.print(game.tick)"
```

### Analysis Commands

```bash
# Analyze belt connectivity
factorioctl analyze belt-reach --at 50,-30

# Find belt networks
factorioctl analyze belt-networks --area 0,0,100,100

# Find gaps in belt lines
factorioctl analyze belt-gaps --area 0,0,100,100
```

## MCP Server

The MCP server exposes Factorio control as tools for LLM agents.

### Running the MCP Server

```bash
# Run with environment variables
FACTORIO_RCON_PASSWORD=yourpassword ./target/debug/mcp
```

### Available MCP Tools

**High-Level (Recommended):**
- `route_belt` - Route belts from A to B using A* pathfinding (avoids obstacles automatically)
- `walk_to` - Walk character to a position
- `craft` - Craft items

**Query:**
- `get_entities` - Get entities in an area
- `get_resources` - Get resources in an area
- `get_character` - Get character position and status
- `get_inventory` - Get character inventory
- `get_tick` - Get current game tick

**Analysis:**
- `analyze_belt_reach` - Analyze belt connectivity from a position
- `analyze_belt_networks` - Find separate belt networks in an area
- `analyze_belt_gaps` - Find gaps in belt lines
- `analyze_inserters` - Analyze inserter pickup/dropoff positions

**Low-Level:**
- `place_entity` - Place a single entity
- `mine_at` - Mine at a position
- `insert_items` - Insert items into an entity
- `remove_entity` - Remove an entity
- `execute_lua` - Execute raw Lua command

## Architecture

```
┌─────────────────┐     ┌──────────────────┐
│  CLI/MCP Server │────▶│  FactorioClient  │
└─────────────────┘     └────────┬─────────┘
                                 │ RCON
                                 ▼
                        ┌────────────────┐
                        │   Factorio     │
                        │  (headless)    │
                        └────────────────┘
```

The tool uses A* pathfinding for routing belts and walking, with collision detection to avoid obstacles. High-level commands are recommended as they handle the complexity of pathfinding and world state management.

## Development

```bash
# Build
cargo build

# Run tests
cargo test

# Run pathfinding integration tests
cargo test --test pathfinding_tests
```

## License

MIT
