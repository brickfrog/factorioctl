# Bug: Character teleport command does not move character

## Command
```bash
./target/release/factorioctl --host localhost --port 27016 --password test_password character teleport "76,-26"
```

## Expected Behavior
Character should be moved to position (76, -26).

## Actual Behavior
Command reports "Teleported to (76, -26)" but character remains at previous position (-13.9, -8.6).

## Error Output
```
Teleported to (76, -26)
```
No error shown, but subsequent `character status` shows character still at old position.

## Context
- Game state: Character was at (-13.9, -8.6) near crashed spaceship
- Attempting to teleport to coal drill area

## Workaround
Use `walk-to` with pathfinding instead of teleport. Walk in stages if distance is large.
