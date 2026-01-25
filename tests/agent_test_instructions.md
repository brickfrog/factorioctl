# Test Agent Instructions

You are testing the `factorioctl` CLI tool against a running Factorio server.

## IMPORTANT: Operating Rules

**Use the precompiled binary only.** Do NOT:
- Edit source code (`src/**/*.rs`)
- Run `cargo build`, `cargo run`, or any compilation commands
- Attempt to fix bugs in the tool

If you encounter bugs or unexpected behavior:
1. Document them in `bugs/` using the template
2. Find a workaround and continue testing
3. Move on - bug fixes happen in separate sessions

## Prerequisites

The test environment should already be set up:
- The `factorioctl` binary is built at `./target/release/factorioctl`
- A Factorio headless server is running on RCON port 27016
- The RCON password is `test_password`

## CLI Usage

All commands use these connection flags:
```bash
./target/release/factorioctl --port 27016 --password test_password <command>
```

For brevity, examples below omit the connection flags.

## Test Scenarios

### 1. Basic Connectivity Test

Verify RCON connection works:

```bash
# Get current game tick
factorioctl get tick

# Expected: Tick: <number> (<seconds>s)
# JSON mode: {"tick": <number>}
```

```bash
# List surfaces
factorioctl get surfaces

# Expected: nauvis (index: 1, daytime: ...)
```

### 2. Character Initialization Test

Create and verify a character entity:

```bash
# Initialize character at spawn
factorioctl character init

# Expected: Entity with name "character" at position near (0, 0)
```

```bash
# Check character status
factorioctl character status

# Expected: valid=true, position, health info
```

### 3. World Query Tests

Query the game world:

```bash
# Find resources near spawn
factorioctl get resources --area -100,-100,100,100

# Expected: List of resource patches (iron-ore, copper-ore, coal, stone)
```

```bash
# Get entities in an area
factorioctl get entities --area -50,-50,50,50

# Expected: List of entities (may be empty initially)
```

```bash
# Get tile information
factorioctl get tile 0,0

# Expected: Tile name and walkability info
```

### 4. Teleportation Test

Move the character:

```bash
# Teleport to a position
factorioctl character teleport 10,10

# Expected: "Teleported to (10, 10)"
```

```bash
# Verify position changed
factorioctl character status

# Expected: Position should be near (10, 10)
```

### 5. Resource Location Test

Find specific resources:

```bash
# Find nearest iron ore from spawn
factorioctl get resources --nearest iron-ore --from 0,0

# Expected: Iron ore patch with center position and amount
```

### 6. Tick Control Test

Test game speed control:

```bash
# Pause the game
factorioctl tick pause

# Get tick (should not change)
factorioctl get tick
sleep 1
factorioctl get tick

# Resume
factorioctl tick resume
```

### 7. JSON Output Test

Verify JSON output mode:

```bash
# Get tick as JSON
factorioctl --output json get tick

# Expected: {"tick": <number>}
```

```bash
# Get resources as JSON
factorioctl --output json get resources --area -50,-50,50,50

# Expected: {"resources": [...]} or similar JSON structure
```

## Full Integration Test Sequence

Run this sequence to test the complete workflow:

```bash
# 1. Verify connection
factorioctl get tick

# 2. Initialize character
factorioctl character init

# 3. Survey the area
factorioctl get resources --area -100,-100,100,100 --output json

# 4. Find iron ore
factorioctl get resources --nearest iron-ore --from 0,0

# 5. Teleport near iron (use coordinates from step 4)
factorioctl character teleport <iron_x>,<iron_y>

# 6. Check inventory (should be empty)
factorioctl character inventory

# 7. Check character status
factorioctl character status
```

## Expected Behaviors

### Success Indicators
- Commands complete without error
- JSON output is valid and parseable
- Positions and values are reasonable
- Character can be created and moved

### Known Limitations
- Mining/crafting require items which may not be available initially
- Entity placement requires items in inventory
- Some commands may return empty results on a fresh map

## Reporting Results

Report test results as:
- PASS: Command worked as expected
- FAIL: Command failed or returned unexpected result
- SKIP: Test could not be run (missing prerequisites)

Include the actual command output for any failures.
