#!/bin/bash
# Cleanup test environment
#
# Stops the running Factorio server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PID_FILE="$PROJECT_ROOT/logs/server.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping server (PID: $PID)..."
        kill "$PID"
        sleep 2
        if kill -0 "$PID" 2>/dev/null; then
            echo "Force killing..."
            kill -9 "$PID"
        fi
        echo "Server stopped."
    else
        echo "Server not running (stale PID file)."
    fi
    rm -f "$PID_FILE"
else
    # Try to find and kill any test server
    PIDS=$(pgrep -f "factorio.*--rcon-port.*27016" || true)
    if [ -n "$PIDS" ]; then
        echo "Found running server(s): $PIDS"
        kill $PIDS 2>/dev/null || true
        echo "Stopped."
    else
        echo "No test server running."
    fi
fi
