# Testing factorioctl

This directory contains test infrastructure for the factorioctl CLI.

## Quick Start

```bash
# 1. Build the CLI and start a test server
./tests/setup.sh

# 2. Run tests (in another terminal)
./tests/run_tests.sh

# 3. Watch the game (optional - see docs/watching.md)
```

## Test Files

- `setup.sh` - Builds CLI, creates map, starts headless server
- `run_tests.sh` - Runs the test suite against the running server
- `agent_test_instructions.md` - Instructions for test agents
- `cleanup.sh` - Stops server and cleans up

## For Test Agents

Test agents should read `agent_test_instructions.md` for:
- Available commands and their usage
- Test scenarios to execute
- Expected outcomes to verify

## Server Ports

- RCON: 27016 (test server)
- Game: 34197 (for spectating)
