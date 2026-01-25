# Bug: Belt pathfinding cannot route through destructible objects

## Command
```bash
./target/release/factorioctl --host localhost --port 27016 --password test_password belt line --from "77,-15" --to "77,-22"
```

## Expected Behavior
Belt pathfinding should be able to plan routes through destructible objects like trees, marking them for removal as part of the placement process.

## Actual Behavior
Belt pathfinding treats trees and other destructible objects as permanent obstacles, preventing belt placement even when the player could manually remove them.

## Error Output
```
Planning belt route from (78,-14) to (78,-22)
Search area: (68,-32) to (88,-4)
Collision map: 125 blocked tiles
Route failed: Goal position is blocked
```

## Context
- Game state: Trying to connect electric mining drill output to main belt
- Trees and other destructible objects in the path

## Workaround
Manually place belts one at a time, or manually clear trees first before using belt routing.
