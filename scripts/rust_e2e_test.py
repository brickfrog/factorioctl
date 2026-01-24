#!/usr/bin/env python3
"""
End-to-end test for the Rust factorioctl CLI.

This script validates that the Rust CLI can communicate with a real Factorio server.

Usage:
    python scripts/rust_e2e_test.py
"""

import subprocess
import time
import sys
from pathlib import Path

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent))
from create_map import create_map, get_factorio_binary
from rcon_client import RconClient

# Constants
PROJECT_ROOT = Path(__file__).parent.parent
SAVE_NAME = "rust_e2e_test"
RCON_PORT = 27017
RCON_PASSWORD = "rust_test_password"
SERVER_SETTINGS = PROJECT_ROOT / "configs" / "test-server.json"
CLI_PATH = PROJECT_ROOT / "target/release/factorioctl"


def run_cli(args):
    """Run the Rust CLI with given arguments."""
    cmd = [str(CLI_PATH)] + args + [
        "--host", "localhost",
        "--port", str(RCON_PORT),
        "--password", RCON_PASSWORD
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.stdout, result.stderr, result.returncode


def main():
    print("=" * 60)
    print("RUST FACTORIOCTL E2E TEST")
    print("=" * 60)

    # Check if CLI exists
    if not CLI_PATH.exists():
        print(f"ERROR: CLI not found at {CLI_PATH}")
        print("Run 'cargo build --release' first")
        return 1

    # Create test map
    print("\n=== Step 1: Create test map ===")
    try:
        save_path = create_map(SAVE_NAME)
        print(f"  Created: {save_path}")
    except Exception as e:
        print(f"  FAIL: {e}")
        return 1

    # Start server
    print("\n=== Step 2: Start Factorio server ===")
    cmd = [
        get_factorio_binary(),
        "--start-server", str(save_path),
        "--rcon-port", str(RCON_PORT),
        "--rcon-password", RCON_PASSWORD,
        "--server-settings", str(SERVER_SETTINGS),
    ]
    server = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print("  Server process started")

    # Wait for RCON
    print("\n=== Step 3: Wait for RCON ===")
    start = time.time()
    while time.time() - start < 30:
        try:
            client = RconClient("localhost", RCON_PORT, RCON_PASSWORD)
            if client.connect():
                client.close()
                break
        except Exception:
            pass
        time.sleep(0.5)
    else:
        print("  FAIL: Server did not start")
        server.terminate()
        return 1
    print("  PASS: Server ready")

    # Run tests
    all_passed = True

    # Test 1: get tick
    print("\n=== Test: get tick ===")
    stdout, stderr, code = run_cli(["get", "tick"])
    print(f"  stdout: {stdout.strip()}")
    if stderr:
        print(f"  stderr: {stderr.strip()}")
    if code == 0 and "tick" in stdout.lower():
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 2: get surfaces
    print("\n=== Test: get surfaces ===")
    stdout, stderr, code = run_cli(["get", "surfaces"])
    print(f"  stdout: {repr(stdout[:200])}")
    if stderr:
        print(f"  stderr: {stderr.strip()}")
    if code == 0 and "nauvis" in stdout.lower():
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 3: get entities (use positive coords to avoid negative number parsing issue)
    print("\n=== Test: get entities ===")
    stdout, stderr, code = run_cli(["get", "entities", "--area", "0,0,20,20"])
    print(f"  stdout: {repr(stdout[:200])}")
    if stderr:
        print(f"  stderr: {stderr.strip()}")
    if code == 0:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 4: get tile
    print("\n=== Test: get tile ===")
    stdout, stderr, code = run_cli(["get", "tile", "0,0"])
    print(f"  stdout: {repr(stdout)}")
    if stderr:
        print(f"  stderr: {stderr.strip()}")
    if code == 0:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 5: JSON output
    print("\n=== Test: JSON output ===")
    stdout, stderr, code = run_cli(["get", "tick", "--output", "json"])
    print(f"  stdout: {stdout.strip()}")
    if code == 0 and "{" in stdout:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 6: character init
    print("\n=== Test: character init ===")
    stdout, stderr, code = run_cli(["character", "init"])
    print(f"  stdout: {stdout.strip()[:200]}...")
    if code == 0:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        if stderr:
            print(f"  stderr: {stderr}")
        all_passed = False

    # Test 7: character status
    print("\n=== Test: character status ===")
    stdout, stderr, code = run_cli(["character", "status"])
    print(f"  stdout: {stdout.strip()[:200]}...")
    if code == 0:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 8: tick pause
    print("\n=== Test: tick pause ===")
    stdout, stderr, code = run_cli(["tick", "pause"])
    print(f"  stdout: {stdout.strip()}")
    if code == 0:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Test 9: tick resume
    print("\n=== Test: tick resume ===")
    stdout, stderr, code = run_cli(["tick", "resume"])
    print(f"  stdout: {stdout.strip()}")
    if code == 0:
        print("  PASS")
    else:
        print(f"  FAIL (exit code: {code})")
        all_passed = False

    # Debug: test via Python RCON
    print("\n=== Debug: Python RCON test ===")
    try:
        client = RconClient("localhost", RCON_PORT, RCON_PASSWORD)
        if client.connect():
            # Simple command
            response = client.execute("/c rcon.print(game.tick)")
            print(f"  Simple command response: {repr(response)}")

            # Multiline command
            lua = '''local result = {}
for _, surface in pairs(game.surfaces) do
    table.insert(result, {
        name = surface.name,
        index = surface.index
    })
end
rcon.print(game.table_to_json(result))'''
            response = client.execute("/c " + lua)
            print(f"  Multiline command response: {repr(response[:200])}")
            client.close()
    except Exception as e:
        print(f"  Python RCON error: {e}")

    # Cleanup
    print("\n=== Cleanup ===")
    server.terminate()
    try:
        server.wait(timeout=5)
    except subprocess.TimeoutExpired:
        server.kill()
    print("  Server stopped")

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
