# Bug: TTS messages are getting cut short

## Command
```bash
./target/release/factorioctl --host localhost --port 27016 --password test_password say "This is a longer message that explains what I'm doing and why I'm doing it."
```

## Expected Behavior
The entire message should be spoken via TTS without truncation.

## Actual Behavior
TTS messages are being cut off before completion, especially for longer messages.

## Error Output
No error output - the command completes but audio playback stops prematurely.

## Context
- Using the `say` command with TTS enabled (default)
- Issue more noticeable with longer messages

## Workaround
Keep messages shorter, or use multiple shorter messages instead of one long message.
