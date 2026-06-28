# factorio-buddy

An AI buddy that plays Factorio *alongside* you — a second character on the
server that acts on its own initiative (walks, mines, surveys, builds, narrates)
while you keep your own body. Chat with it to redirect; otherwise it does its own
thing.

Under the hood it's two parts living in one repo:

- **`src/`** — `factorioctl`, a Rust CLI + MCP server that controls Factorio over
  RCON-injected Lua. This is the "calculator" layer: pathfinding, belt routing,
  zones, blueprints, agent-scoped character binding, honest action feedback. It
  gives the LLM real tools instead of making it reason about pixels.
- **`companion/`** — the bridge + Factorio mod that turn the engine into an
  autonomous teammate: per-agent `claude -p` loops with a self-driven heartbeat,
  an in-game chat GUI, and a deterministic on-tick mod for multiplayer.

> Status: research / play project. It genuinely works — an agent will boot,
> spawn a body, and start playing autonomously — but it's held together with
> enthusiasm. Use at your own risk.

## What works today

- **Autonomy loop** — the agent self-prompts when idle and keeps playing on its
  own; a chat message supersedes the next tick. (`companion/bridge/pipe.py`)
- **Its own body** — each named agent gets a character bound in both the mod and
  factorioctl registries, so every walk/mine/build tool resolves it.
- **The tool layer** — map/ASCII rendering, A* pathing, belt routing (incl.
  underground + zones), resource scanning, blueprints, research, crafting.
- **Pluggable model** — routes through any Anthropic-compatible endpoint. We run
  it on z.ai's GLM so it doesn't touch your Claude quota (see
  `companion/bridge/.env.example`).

## In progress

- **Deterministic multiplayer movement** — movement currently runs in
  factorioctl's server-side driver, which stutters/desyncs for a connected human
  client. Moving the walk loop into the mod's lockstep `on_tick` (with
  factorioctl routing through the mod's remote) is the active work.

## Quickstart

```bash
# 1. Build the engine (CLI + MCP server)
cargo build --release

# 2. Configure the model backend (z.ai GLM, or any Anthropic-compatible API)
cp companion/bridge/.env.example companion/bridge/.env   # then fill in
$EDITOR companion/bridge/.env

# 3. Boot a headless server + the bridge (one AI agent on Nauvis)
cd companion
just play          # fresh world; `just resume` keeps the existing save

# 4. Join from your Steam client: Multiplayer -> localhost:34197
#    Watch your buddy play. Open the in-game chat panel to talk to it.
```

The `companion/justfile` has the rest: `just server`, `just bridge`, `just doctor`,
`just logs`. Factorio binary path is configurable via `FACTORIO_BIN`.

## Repo layout

```
src/                 factorioctl — Rust CLI + MCP server (the engine)
companion/           the autonomous-companion bridge + Factorio mod
  bridge/            python: claude -p agent loops, RCON, telemetry
  mod/claude-interface/   Factorio mod: chat GUI, character registry, on_tick
  justfile run.sh    server + bridge orchestration
.choir/              orchestration + audit pipeline state
```

## Origins & credits

This project stands on two pieces of prior work, both gratefully credited:

- **The engine** is a fork of [`MarkMcCaskey/factorioctl`](https://github.com/MarkMcCaskey/factorioctl)
  — the original "kubectl for Factorio" CLI + MCP server, vibe-coded in a weekend.
  Mark's original writeup and lessons-learned (well worth reading) live in that
  repo. We've since diverged substantially: agent-scoped character binding,
  RCON-transport and honest-feedback hardening, a security audit pass, and the
  whole autonomous-companion layer.
- **The companion** (`companion/`) is vendored from
  [`QRY91/claude-in-factorio`](https://github.com/QRY91/claude-in-factorio)
  at commit `55c6020`, and substantially extended here (autonomy loop, unified
  character registry, monorepo integration). See `NOTICE` and
  `companion/LICENSE`.

Both upstreams were inactive when we vendored/forked; this repo consolidates them
into one build + review pipeline.

## License

The factorioctl engine retains its original license. Vendored companion code
retains its original license (`companion/LICENSE`); see `NOTICE` for attribution.
