#!/usr/bin/env python3
"""
Create a Factorio map using the test configuration.

Usage:
    python scripts/create_map.py --name test
    python scripts/create_map.py --name mymap --config configs/custom-map-gen.json
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent
DEFAULT_CONFIG = PROJECT_ROOT / "configs" / "test-map-gen.json"
SAVES_DIR = PROJECT_ROOT / "saves"

# Use separate data directory so map creation doesn't conflict with Steam client
SERVER_DATA_DIR = PROJECT_ROOT / ".factorio-server"

# Factorio binary location (macOS Steam installation)
FACTORIO_BINARY = Path.home() / "Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio"

def get_factorio_binary() -> str:
    """Get the path to the Factorio binary."""
    # Check environment variable first
    if "FACTORIO_BINARY" in os.environ:
        return os.environ["FACTORIO_BINARY"]

    # Use default Steam installation path
    if FACTORIO_BINARY.exists():
        return str(FACTORIO_BINARY)

    # Fall back to hoping it's in PATH
    return "factorio"


def create_map(name: str, config_path: Path | None = None) -> Path:
    """
    Create a new Factorio map.

    Args:
        name: Name for the save file (without extension)
        config_path: Path to map-gen-settings.json (defaults to test config)

    Returns:
        Path to the created save file
    """
    config = config_path or DEFAULT_CONFIG
    save_path = SAVES_DIR / f"{name}.zip"

    # Ensure saves directory exists
    SAVES_DIR.mkdir(parents=True, exist_ok=True)

    # Ensure server data directory exists (for separate config to avoid lock conflicts)
    SERVER_DATA_DIR.mkdir(parents=True, exist_ok=True)

    # Remove existing save if present
    if save_path.exists():
        print(f"Removing existing save: {save_path}")
        save_path.unlink()

    # Use --config to specify separate data directory (avoids lock conflict with Steam client)
    cmd = [
        get_factorio_binary(),
        "--config", str(SERVER_DATA_DIR / "config.ini"),
        "--create", str(save_path),
        "--map-gen-settings", str(config),
    ]

    print(f"Creating map: {name}")
    print(f"Config: {config}")
    print(f"Command: {' '.join(cmd)}")
    print()

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("STDERR:", result.stderr)
        print("STDOUT:", result.stdout)
        raise RuntimeError(f"Failed to create map: {result.returncode}")

    if not save_path.exists():
        raise RuntimeError(f"Map was not created at {save_path}")

    print(f"Map created: {save_path}")
    print(f"Size: {save_path.stat().st_size / 1024:.1f} KB")

    return save_path


def main():
    parser = argparse.ArgumentParser(description="Create a Factorio test map")
    parser.add_argument(
        "--name", "-n",
        default="test",
        help="Name for the save file (default: test)"
    )
    parser.add_argument(
        "--config", "-c",
        type=Path,
        help="Path to map-gen-settings.json (default: configs/test-map-gen.json)"
    )

    args = parser.parse_args()

    try:
        save_path = create_map(args.name, args.config)
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
