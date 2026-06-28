"""Persistent per-agent objective ledger for bridge autonomy continuity."""

import json
import re
from datetime import datetime
from pathlib import Path


LEDGER_RE = re.compile(r"<ledger>(.*?)</ledger>", re.DOTALL | re.IGNORECASE)


def _ledger_file(agent_name: str) -> Path:
    return Path(__file__).resolve().parent / f".ledger-{agent_name}.json"


def default_ledger() -> dict:
    return {
        "objective": "",
        "plan_steps": [],
        "progress_notes": [],
        "updated_at": "",
    }


def load_ledger(agent_name: str) -> dict:
    try:
        data = json.loads(_ledger_file(agent_name).read_text())
        if isinstance(data, dict):
            return data
        return default_ledger()
    except (json.JSONDecodeError, OSError):
        return default_ledger()


def save_ledger(agent_name: str, ledger: dict) -> None:
    try:
        _ledger_file(agent_name).write_text(json.dumps(ledger) + "\n")
    except (OSError, TypeError):
        return None


def parse_ledger_trailer(text: str) -> dict | None:
    match = LEDGER_RE.search(text)
    if not match:
        return None

    parsed = {}
    plan_steps = []
    saw_plan = False
    in_plan = False

    for raw_line in match.group(1).splitlines():
        line = raw_line.strip()
        if not line:
            continue
        key, sep, value = line.partition(":")
        key_lower = key.strip().lower()
        if sep and key_lower == "objective":
            parsed["objective"] = value.strip()
            in_plan = False
        elif sep and key_lower == "plan":
            saw_plan = True
            in_plan = True
        elif sep and key_lower == "progress":
            parsed["progress"] = value.strip()
            in_plan = False
        elif in_plan and line.startswith("- "):
            plan_steps.append(line[2:].strip())

    if saw_plan:
        parsed["plan_steps"] = [step for step in plan_steps if step]

    return parsed


def apply_ledger_update(agent_name: str, text: str) -> dict:
    parsed = parse_ledger_trailer(text)
    current = load_ledger(agent_name)
    if parsed is None:
        return current

    ledger = {
        "objective": str(current.get("objective", "")),
        "plan_steps": list(current.get("plan_steps", [])),
        "progress_notes": list(current.get("progress_notes", [])),
        "updated_at": str(current.get("updated_at", "")),
    }

    objective = parsed.get("objective", "")
    if objective:
        ledger["objective"] = objective
        ledger["plan_steps"] = list(parsed.get("plan_steps", []))
    elif "plan_steps" in parsed:
        ledger["plan_steps"] = list(parsed["plan_steps"])

    progress = parsed.get("progress", "")
    if progress:
        ledger["progress_notes"].append(progress)
        ledger["progress_notes"] = ledger["progress_notes"][-10:]

    ledger["updated_at"] = datetime.now().isoformat()
    save_ledger(agent_name, ledger)
    return ledger


def strip_ledger_trailer(text: str) -> str:
    if not LEDGER_RE.search(text):
        return text
    stripped = LEDGER_RE.sub("", text)
    stripped = re.sub(r"\n{3,}", "\n\n", stripped)
    return stripped.strip()


def render_ledger(ledger: dict) -> str:
    objective = str(ledger.get("objective", "")).strip()
    if not objective:
        return ""

    lines = [
        f"Continuity ledger: continue the committed objective, do not restart it: {objective}",
    ]
    plan_steps = ledger.get("plan_steps", [])
    if plan_steps:
        lines.append("Plan:")
        for index, step in enumerate(plan_steps, start=1):
            lines.append(f"{index}. {step}")
    progress_notes = ledger.get("progress_notes", [])[-3:]
    if progress_notes:
        lines.append("Recent progress:")
        for note in progress_notes:
            lines.append(f"- {note}")
    return "\n".join(lines)
