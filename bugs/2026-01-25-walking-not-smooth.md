# Bug: Walking movement is not smooth

## Command
```bash
./target/release/factorioctl --host localhost --port 27016 --password test_password walk-to "75,-17" -r -p
```

## Expected Behavior
Character should walk smoothly to the destination with fluid movement.

## Actual Behavior
Walking feels choppy/jerky. Character gets stuck easily and pathfinding often reports "Blocked or stuck" even when there appears to be a clear path.

## Error Output
```
Walking from (78, -23) to (76, -16)...
Stopped at (78, -23) - Blocked or stuck
Distance walked: 0.0 tiles
```

## Context
- Game state: Character was in coal mining area with belts and drills nearby
- Multiple attempts to walk short distances failed

## Workaround
Walk in smaller increments. Try different intermediate waypoints. Sometimes walking without pathfinding (-p flag) works better for short distances.
