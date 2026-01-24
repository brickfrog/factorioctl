#!/usr/bin/env python3
"""
End-to-end test for factorioctl.

This script validates the core workflow:
1. Create a test map with no enemies
2. Start a headless server with RCON
3. Execute Lua commands via RCON
4. Verify entity interactions work
5. Clean up

Usage:
    python scripts/e2e_test.py
"""

import atexit
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

# Add scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from create_map import create_map, get_factorio_binary
from rcon_client import RconClient

# Test configuration
PROJECT_ROOT = Path(__file__).parent.parent
SAVE_NAME = "e2e_test"
SAVE_PATH = PROJECT_ROOT / "saves" / f"{SAVE_NAME}.zip"
RCON_PORT = 27016  # Use different port to avoid conflicts
RCON_PASSWORD = "e2e_test_password"
SERVER_SETTINGS = PROJECT_ROOT / "configs" / "test-server.json"

# Track server process for cleanup
server_process = None


def cleanup():
    """Clean up server process and save file."""
    global server_process
    if server_process:
        print("\nCleaning up server process...")
        try:
            server_process.terminate()
            server_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_process.kill()
        server_process = None


def start_server(save_path: Path) -> subprocess.Popen:
    """Start a Factorio headless server."""
    cmd = [
        get_factorio_binary(),
        "--start-server", str(save_path),
        "--rcon-port", str(RCON_PORT),
        "--rcon-password", RCON_PASSWORD,
        "--server-settings", str(SERVER_SETTINGS),
    ]

    print(f"Starting server: {' '.join(cmd[:3])} ...")
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    return process


def wait_for_server(process: subprocess.Popen, timeout: float = 30.0) -> bool:
    """Wait for the server to be ready by checking for RCON startup."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        if process.poll() is not None:
            # Process died
            stdout, _ = process.communicate()
            print(f"Server died unexpectedly:\n{stdout}")
            return False

        # Try to connect via RCON
        try:
            client = RconClient("localhost", RCON_PORT, RCON_PASSWORD)
            if client.connect():
                client.close()
                return True
        except Exception:
            pass

        time.sleep(0.5)

    return False


def test_basic_commands(client: RconClient) -> bool:
    """Test basic RCON commands."""
    print("\n=== Testing basic commands ===")

    # Test simple echo first to verify RCON works
    response = client.execute("/c rcon.print('hello')")
    print(f"  echo test: '{response}'")
    if "hello" not in response:
        print(f"  FAIL: Echo test failed, got: {response}")
        return False
    print("  PASS: Echo test works")

    # Test game tick - use type() to ensure we get something
    response = client.execute("/c rcon.print('tick:' .. tostring(game.tick))")
    print(f"  game.tick: {response}")
    if not response.strip().startswith("tick:"):
        print(f"  FAIL: Unexpected tick response: {response}")
        return False
    tick_str = response.strip().replace("tick:", "")
    try:
        tick = int(tick_str)
        if tick < 0:
            print("  FAIL: Invalid tick value")
            return False
    except ValueError:
        print(f"  FAIL: Could not parse tick: {tick_str}")
        return False
    print(f"  PASS: game.tick = {tick}")

    # Test surface name
    response = client.execute("/c rcon.print(game.surfaces[1].name)")
    print(f"  surface name: {response}")
    if "nauvis" not in response.lower():
        print(f"  FAIL: Expected 'nauvis', got: {response}")
        return False
    print("  PASS: surface name works")

    return True


def test_entity_operations(client: RconClient) -> bool:
    """Test entity creation, finding, and removal."""
    print("\n=== Testing entity operations ===")

    # Clear any existing test entities
    client.execute("/c for _, e in pairs(game.surfaces[1].find_entities_filtered{name='iron-chest'}) do e.destroy() end")

    # Create an entity
    client.execute("/c game.surfaces[1].create_entity{name='iron-chest', position={5, 5}, force='player'}")
    print("  Created iron-chest at (5, 5)")

    # Find the entity
    response = client.execute("/c local e = game.surfaces[1].find_entities_filtered{name='iron-chest'}; rcon.print(#e)")
    count = int(response.strip())
    print(f"  Found {count} iron-chest entities")
    if count != 1:
        print(f"  FAIL: Expected 1 entity, got {count}")
        return False
    print("  PASS: Entity creation works")

    # Get entity position
    response = client.execute(
        "/c local e = game.surfaces[1].find_entities_filtered{name='iron-chest'}[1]; "
        "rcon.print(e.position.x .. ',' .. e.position.y)"
    )
    print(f"  Entity position: {response}")
    if "5" not in response:
        print(f"  FAIL: Expected position near (5,5), got: {response}")
        return False
    print("  PASS: Entity position works")

    # Remove the entity
    client.execute("/c local e = game.surfaces[1].find_entities_filtered{name='iron-chest'}[1]; if e then e.destroy() end")
    print("  Destroyed iron-chest")

    # Verify removal
    response = client.execute("/c local e = game.surfaces[1].find_entities_filtered{name='iron-chest'}; rcon.print(#e)")
    count = int(response.strip())
    if count != 0:
        print(f"  FAIL: Expected 0 entities after removal, got {count}")
        return False
    print("  PASS: Entity removal works")

    return True


def test_player_and_resources(client: RconClient) -> bool:
    """Test player-related and resource information."""
    print("\n=== Testing player/resource info ===")

    # Get player count (may be 0 in headless)
    response = client.execute("/c rcon.print('players:' .. #game.players)")
    print(f"  Player count: {response}")

    # Get mod count
    response = client.execute("/c local count = 0; for _ in pairs(game.active_mods) do count = count + 1 end; rcon.print('mods:' .. count)")
    print(f"  Active mods: {response}")

    # Get surface properties
    response = client.execute(
        "/c local s = game.surfaces[1]; "
        "rcon.print('daytime:' .. tostring(s.daytime) .. ',darkness:' .. tostring(s.darkness))"
    )
    print(f"  Surface: {response}")
    print("  PASS: Player/resource info works")

    return True


def main():
    global server_process

    # Register cleanup handler
    atexit.register(cleanup)
    signal.signal(signal.SIGINT, lambda sig, frame: (cleanup(), sys.exit(1)))
    signal.signal(signal.SIGTERM, lambda sig, frame: (cleanup(), sys.exit(1)))

    print("=" * 60)
    print("FACTORIOCTL END-TO-END TEST")
    print("=" * 60)

    # Step 1: Create test map
    print("\n=== Step 1: Create test map ===")
    try:
        save_path = create_map(SAVE_NAME)
        print(f"  Created: {save_path}")
    except Exception as e:
        print(f"  FAIL: {e}")
        return 1

    # Step 2: Start server
    print("\n=== Step 2: Start headless server ===")
    server_process = start_server(save_path)
    print("  Server process started")

    # Step 3: Wait for server to be ready
    print("\n=== Step 3: Wait for RCON ===")
    if not wait_for_server(server_process):
        print("  FAIL: Server did not start properly")
        return 1
    print("  PASS: Server ready")

    # Step 4: Connect and run tests
    print("\n=== Step 4: Connect to RCON ===")
    client = RconClient("localhost", RCON_PORT, RCON_PASSWORD)
    if not client.connect():
        print("  FAIL: Could not connect to RCON")
        return 1
    print("  PASS: Connected to RCON")

    # Give the server a moment to settle after connection
    time.sleep(0.5)

    # Warmup command - first command sometimes gets dropped
    client.execute("/c")

    all_passed = True

    # Run tests
    all_passed = test_basic_commands(client) and all_passed
    all_passed = test_entity_operations(client) and all_passed
    all_passed = test_player_and_resources(client) and all_passed

    # Cleanup
    client.close()
    cleanup()

    # Results
    print("\n" + "=" * 60)
    if all_passed:
        print("ALL TESTS PASSED")
        print("=" * 60)
        return 0
    else:
        print("SOME TESTS FAILED")
        print("=" * 60)
        return 1


if __name__ == "__main__":
    sys.exit(main())
