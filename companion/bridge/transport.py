"""Bridge <-> Factorio game transport: RCON commands out, JSONL file in."""

import json
from pathlib import Path

from rcon import RCONClient, lua_long_string


def send_response(rcon: RCONClient, player_index: int, agent_name: str, text: str):
    encoded = lua_long_string(text)
    agent_encoded = lua_long_string(agent_name)
    lua = f'/silent-command remote.call("claude_interface", "receive_response", {player_index}, {agent_encoded}, {encoded})'
    rcon.execute(lua)


def send_tool_status(rcon: RCONClient, player_index: int, agent_name: str, tool_name: str):
    agent_encoded = lua_long_string(agent_name)
    encoded = lua_long_string(tool_name)
    lua = f'/silent-command remote.call("claude_interface", "tool_status", {player_index}, {agent_encoded}, {encoded})'
    rcon.execute(lua)


def set_status(rcon: RCONClient, player_index: int, status: str):
    encoded = lua_long_string(status)
    lua = f'/silent-command remote.call("claude_interface", "set_status", {player_index}, {encoded})'
    rcon.execute(lua)


def register_agent(rcon: RCONClient, agent_name: str, label: str | None = None):
    encoded = lua_long_string(agent_name)
    if label:
        label_encoded = lua_long_string(label)
        lua = f'/silent-command remote.call("claude_interface", "register_agent", {encoded}, {label_encoded})'
    else:
        lua = f'/silent-command remote.call("claude_interface", "register_agent", {encoded})'
    rcon.execute(lua)


def unregister_agent(rcon, agent_name: str):
    encoded = lua_long_string(agent_name)
    lua = f'/silent-command remote.call("claude_interface", "unregister_agent", {encoded})'
    rcon.execute(lua)


def setup_surfaces(rcon, planets: list[str]) -> dict[str, str]:
    """Ensure planet surfaces exist. Creates them if missing.
    Returns {planet: status} where status is 'exists' or 'created'."""
    results = {}
    for planet in planets:
        planet_encoded = lua_long_string(planet)
        lua = f'rcon.print(remote.call("claude_interface", "ensure_surface", {planet_encoded}))'
        result = rcon.execute(f'/silent-command {lua}').strip()
        results[planet] = result
    return results


def pre_place_character(rcon, agent_name: str, planet: str, spawn_offset: int = 0) -> str:
    """Create or teleport an agent's character to the specified planet surface.
    Forces terrain generation around spawn so agents don't land in void.
    spawn_offset shifts the X position to avoid overlapping with the player.
    Returns status: already_placed, teleported, created, surface_not_found, creation_failed.

    All character state lives in mod storage (synced in MP) — no _G.global usage."""
    spawn_x = spawn_offset * 5 + 5  # offset from player spawn at (0,0)
    agent_encoded = lua_long_string(agent_name)
    planet_encoded = lua_long_string(planet)
    lua_code = (
        'rcon.print(remote.call("claude_interface", "pre_place_character", '
        f'{agent_encoded}, {planet_encoded}, {spawn_x}))'
    )
    result = rcon.execute(f'/silent-command {lua_code}')
    return result.strip()


def set_spectator_mode(rcon, enabled: bool = True):
    """Enable/disable spectator mode via the mod. When enabled, all connecting
    players are automatically set to spectator (no character body).
    Persists across player joins — no timing issues."""
    val = "true" if enabled else "false"
    lua = f'/silent-command remote.call("claude_interface", "set_spectator_mode", {val})'
    rcon.execute(lua)


def check_mod_loaded(rcon) -> bool:
    result = rcon.execute(
        '/silent-command rcon.print(remote.interfaces["claude_interface"] and "yes" or "no")'
    )
    return result.strip() == "yes"


class InputWatcher:
    def __init__(self, input_file: Path):
        self.input_file = input_file
        self.last_size = 0
        if input_file.exists():
            self.last_size = input_file.stat().st_size

    def poll(self) -> list[dict]:
        if not self.input_file.exists():
            return []
        current_size = self.input_file.stat().st_size
        if current_size <= self.last_size:
            return []
        messages = []
        with open(self.input_file, "r") as f:
            f.seek(self.last_size)
            new_data = f.read()
        self.last_size = current_size
        for line in new_data.strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
                if msg.get("message"):
                    messages.append(msg)
            except json.JSONDecodeError:
                continue
        return messages
