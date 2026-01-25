# Bug: Exclamation marks rendered as "\!" in game chat

## Command
```bash
./target/release/factorioctl --host localhost --port 27016 --password test_password say "Hello! This is exciting!"
```

## Expected Behavior
Message should appear in game as: `Hello! This is exciting!`

## Actual Behavior
Message appears in game as: `Hello\! This is exciting\!`

The exclamation mark is being escaped with a backslash.

## Error Output
No error - command succeeds but text is malformed in game.

## Context
- Affects all messages containing "!"
- Both in-game chat display and possibly TTS

## Workaround
Avoid using exclamation marks in messages, or accept the escaped display.
