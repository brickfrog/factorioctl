# Bug Reports

This folder contains bug reports discovered during play sessions.

## Filing a Bug

When you encounter unexpected behavior with `factorioctl`, create a new file in this folder:

**Filename format:** `YYYY-MM-DD-short-description.md`

**Template:**

```markdown
# Bug: [Short Description]

## Command
```bash
[exact command that caused the issue]
```

## Expected Behavior
[what should have happened]

## Actual Behavior
[what actually happened]

## Error Output
```
[paste any error messages or unexpected output]
```

## Context
- Game state: [relevant game state, e.g., "character at (50, 20)"]
- Inventory: [relevant inventory items if applicable]
- Related entities: [nearby entities if relevant]

## Workaround
[if you found a workaround, document it here]
```

## Important

Do NOT attempt to fix bugs during play sessions. The purpose of this folder is to:
1. Document issues for later debugging
2. Track workarounds used
3. Prevent getting distracted from the play session goal

Bugs will be addressed in dedicated development sessions, not during gameplay.
