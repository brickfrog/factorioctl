"""Load bridge/ test modules for root-level unittest names."""

import importlib.util
from pathlib import Path
import sys


def load(module_name: str, target_globals: dict) -> None:
    bridge_dir = Path(__file__).resolve().parent / "bridge"
    bridge_path = str(bridge_dir)
    if bridge_path not in sys.path:
        sys.path.insert(0, bridge_path)

    spec = importlib.util.spec_from_file_location(
        f"_bridge_{module_name}",
        bridge_dir / f"{module_name}.py",
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load bridge/{module_name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    for name, value in vars(module).items():
        if not name.startswith("_"):
            target_globals[name] = value
