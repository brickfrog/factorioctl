#!/bin/bash
# Setup test environment for factorioctl
#
# This script:
# 1. Builds the Rust CLI in release mode
# 2. Creates a test map (if needed)
# 3. Starts a headless Factorio server
#
# Usage: ./tests/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Configuration
SAVE_NAME="test_map"
RCON_PORT=27016
RCON_PASSWORD="test_password"
GAME_PORT=34197

# Use separate data directory so headless server doesn't conflict with Steam client
SERVER_DATA_DIR="$PROJECT_ROOT/.factorio-server"

echo "=== factorioctl Test Setup ==="
echo ""

# Step 1: Build the CLI
echo "Building factorioctl (release mode)..."
cargo build --release --quiet
echo "  Built: ./target/release/factorioctl"
echo ""

# Step 2: Create test map if needed
SAVE_PATH="$PROJECT_ROOT/saves/${SAVE_NAME}.zip"
if [ ! -f "$SAVE_PATH" ]; then
    echo "Creating test map..."
    python3 scripts/create_map.py --name "$SAVE_NAME" --config configs/test-map-gen.json
    echo "  Created: $SAVE_PATH"
else
    echo "Using existing test map: $SAVE_PATH"
fi
echo ""

# Step 3: Check if server is already running
if pgrep -f "factorio.*--start-server.*${SAVE_NAME}" > /dev/null; then
    echo "Server already running. Stop it with: ./tests/cleanup.sh"
    exit 1
fi

# Step 4: Find Factorio binary
FACTORIO_BIN=""
STEAM_PATH="$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio"
if [ -f "$STEAM_PATH" ]; then
    FACTORIO_BIN="$STEAM_PATH"
elif command -v factorio &> /dev/null; then
    FACTORIO_BIN="$(which factorio)"
else
    echo "ERROR: Factorio not found. Please install Factorio or set FACTORIO_PATH."
    exit 1
fi
echo "Using Factorio: $FACTORIO_BIN"
echo ""

# Step 5: Start headless server
echo "Starting headless server..."
echo "  RCON port: $RCON_PORT"
echo "  RCON password: $RCON_PASSWORD"
echo "  Game port: $GAME_PORT (for spectating)"
echo "  Data dir: $SERVER_DATA_DIR"
echo ""

# Create directories
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$SERVER_DATA_DIR"
LOG_FILE="$PROJECT_ROOT/logs/server.log"

# Use --config to specify separate data directory (avoids lock conflict with Steam client)
"$FACTORIO_BIN" \
    --config "$SERVER_DATA_DIR/config.ini" \
    --start-server "$SAVE_PATH" \
    --rcon-port "$RCON_PORT" \
    --rcon-password "$RCON_PASSWORD" \
    --port "$GAME_PORT" \
    --server-settings "$PROJECT_ROOT/configs/test-server.json" \
    > "$LOG_FILE" 2>&1 &

SERVER_PID=$!
echo "$SERVER_PID" > "$PROJECT_ROOT/logs/server.pid"

echo "Server starting (PID: $SERVER_PID)..."
echo "Log file: $LOG_FILE"
echo ""

# Wait for server to be ready
echo "Waiting for RCON to be available..."
for i in {1..30}; do
    if ./target/release/factorioctl --port "$RCON_PORT" --password "$RCON_PASSWORD" get tick 2>/dev/null; then
        echo ""
        echo "=== Server Ready ==="
        echo ""
        echo "Test with:"
        echo "  ./target/release/factorioctl --port $RCON_PORT --password $RCON_PASSWORD get tick"
        echo ""
        echo "Stop with:"
        echo "  ./tests/cleanup.sh"
        echo ""
        echo "Watch the game:"
        echo "  See docs/watching.md for instructions"
        exit 0
    fi
    sleep 1
    echo -n "."
done

echo ""
echo "ERROR: Server did not start in time. Check $LOG_FILE"
exit 1
