# Bug: Craft command should automatically handle intermediate products

## Command
```bash
./target/release/factorioctl --host localhost --port 27016 --password test_password craft electric-mining-drill --count 2
```

## Expected Behavior
When crafting an item that requires intermediate products (like iron-gear-wheels for an electric-mining-drill), the system should automatically queue the intermediate crafts if the player has the raw materials.

## Actual Behavior
Only queues crafts for items where all direct ingredients are available. User must manually craft intermediate products first (e.g., craft iron-gear-wheels, then craft electric-mining-drill).

## Error Output
No error - just crafts fewer items than requested because intermediates weren't available.

## Context
- Inventory had iron-plates but not enough iron-gear-wheels
- Recipe needs 5 iron-gear-wheels per drill
- Had to manually craft gear wheels first

## Workaround
Manually check recipe requirements and craft intermediate products before crafting the final item.
