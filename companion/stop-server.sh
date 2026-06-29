#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
STDIN_KEEPER_PID_FILE="$PROJECT_ROOT/logs/server.stdin.pid"
STDIN_FIFO="$PROJECT_ROOT/logs/server.stdin"

if [ -f "$PROJECT_ROOT/logs/server.pid" ]; then
    PID=$(cat "$PROJECT_ROOT/logs/server.pid")
    if kill "$PID" 2>/dev/null; then
        echo "Server (PID $PID) stopped."
    else
        echo "PID $PID not running."
    fi
    rm -f "$PROJECT_ROOT/logs/server.pid"
else
    if pkill -f "factorio.*--start-server" 2>/dev/null; then
        echo "Server stopped."
    else
        echo "No server found."
    fi
fi

if [ -f "$STDIN_KEEPER_PID_FILE" ]; then
    KEEPER_PID=$(cat "$STDIN_KEEPER_PID_FILE")
    kill "$KEEPER_PID" 2>/dev/null || true
    rm -f "$STDIN_KEEPER_PID_FILE"
fi
rm -f "$STDIN_FIFO"
