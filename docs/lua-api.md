# Factorio Lua API Reference

This document covers useful Lua API patterns for interacting with Factorio via RCON.

## Global Objects

| Object | Description |
|--------|-------------|
| `game` | Main game object (LuaGameScript) |
| `rcon` | RCON interface for sending responses |
| `script` | Event registration and mod data |

## Returning Data to RCON

Always use `rcon.print()` to send data back:

```lua
/c rcon.print("Hello!")
/c rcon.print(tostring(game.tick))
/c rcon.print(serpent.line(some_table))  -- Serialize tables
```

## Game State

### Basic Info

```lua
-- Current game tick (60 ticks = 1 second)
/c rcon.print(game.tick)

-- Game speed multiplier
/c rcon.print(game.speed)

-- Is this multiplayer?
/c rcon.print(tostring(game.is_multiplayer()))
```

### Players

```lua
-- Player count
/c rcon.print(#game.players)

-- List player names
/c for _, p in pairs(game.players) do rcon.print(p.name) end

-- Get specific player
/c local p = game.get_player(1); rcon.print(p and p.name or "none")
```

### Forces

```lua
-- List forces
/c for name, force in pairs(game.forces) do rcon.print(name) end

-- Get player force
/c local f = game.forces.player; rcon.print(f.name)
```

## Surfaces (Maps)

### Accessing Surfaces

```lua
-- Get the main surface (nauvis)
/c local s = game.surfaces[1]; rcon.print(s.name)

-- By name
/c local s = game.get_surface("nauvis"); rcon.print(s.name)

-- List all surfaces
/c for _, s in pairs(game.surfaces) do rcon.print(s.name) end
```

### Surface Properties

```lua
-- Time of day (0-1, 0.5 = noon)
/c rcon.print(game.surfaces[1].daytime)

-- Darkness level
/c rcon.print(game.surfaces[1].darkness)
```

## Entities

### Creating Entities

```lua
-- Create at position
/c game.surfaces[1].create_entity{name="iron-chest", position={0,0}}

-- With force ownership
/c game.surfaces[1].create_entity{name="iron-chest", position={10,10}, force="player"}

-- Create assembler with recipe
/c local e = game.surfaces[1].create_entity{name="assembling-machine-1", position={5,5}, force="player"}
/c e.set_recipe("iron-gear-wheel")
```

### Finding Entities

```lua
-- All entities in area
/c local e = game.surfaces[1].find_entities({{-10,-10},{10,10}}); rcon.print(#e)

-- By name
/c local e = game.surfaces[1].find_entities_filtered{name="iron-chest"}; rcon.print(#e)

-- By type
/c local e = game.surfaces[1].find_entities_filtered{type="container"}; rcon.print(#e)

-- Near position
/c local e = game.surfaces[1].find_entities_filtered{position={0,0}, radius=50}; rcon.print(#e)

-- Multiple filters
/c local e = game.surfaces[1].find_entities_filtered{
    type="resource",
    name={"iron-ore", "copper-ore"},
    area={{-100,-100},{100,100}}
}; rcon.print(#e)
```

### Entity Properties

```lua
-- Position
/c local e = game.surfaces[1].find_entities_filtered{name="iron-chest"}[1]
/c rcon.print(e.position.x .. "," .. e.position.y)

-- Health
/c rcon.print(e.health .. "/" .. e.prototype.max_health)

-- Inventory
/c local inv = e.get_inventory(defines.inventory.chest)
/c rcon.print("items: " .. inv.get_item_count())
```

### Destroying Entities

```lua
-- Destroy specific entity
/c local e = game.surfaces[1].find_entities_filtered{name="iron-chest"}[1]
/c if e then e.destroy() end

-- Destroy all of type
/c for _, e in pairs(game.surfaces[1].find_entities_filtered{name="iron-chest"}) do e.destroy() end
```

## Resources

### Finding Resources

```lua
-- Find all resource patches
/c local r = game.surfaces[1].find_entities_filtered{type="resource"}
/c rcon.print("resource patches: " .. #r)

-- Find specific ore
/c local r = game.surfaces[1].find_entities_filtered{name="iron-ore", area={{-100,-100},{100,100}}}
/c local total = 0; for _, e in pairs(r) do total = total + e.amount end
/c rcon.print("iron ore: " .. total)
```

## Tiles

### Reading Tiles

```lua
-- Get tile at position
/c local t = game.surfaces[1].get_tile(0, 0); rcon.print(t.name)

-- Check if position is water
/c local t = game.surfaces[1].get_tile(10, 10)
/c rcon.print(tostring(t.collides_with("player-layer")))
```

### Modifying Tiles

```lua
-- Set tile
/c game.surfaces[1].set_tiles({{name="concrete", position={0,0}}})

-- Set multiple tiles
/c local tiles = {}
/c for x=-5,5 do for y=-5,5 do table.insert(tiles, {name="concrete", position={x,y}}) end end
/c game.surfaces[1].set_tiles(tiles)
```

## Recipes and Technology

### Recipes

```lua
-- List all recipes
/c for name, recipe in pairs(game.forces.player.recipes) do
    if recipe.enabled then rcon.print(name) end
end

-- Enable a recipe
/c game.forces.player.recipes["advanced-circuit"].enabled = true
```

### Technology

```lua
-- Research a technology
/c game.forces.player.technologies["automation"].researched = true

-- Research all
/c for _, tech in pairs(game.forces.player.technologies) do tech.researched = true end
```

## Useful Patterns

### JSON-like Output

```lua
-- Use serpent for table serialization
/c rcon.print(serpent.line({tick=game.tick, players=#game.players}))

-- Custom JSON building
/c local info = string.format('{"tick":%d,"players":%d}', game.tick, #game.players)
/c rcon.print(info)
```

### Error Handling

```lua
-- Use pcall for safe execution
/c local ok, err = pcall(function()
    game.surfaces[1].create_entity{name="invalid", position={0,0}}
end)
/c rcon.print(ok and "success" or ("error: " .. tostring(err)))
```

### Area Scanning

```lua
-- Scan area for resources
/c local area = {{-100,-100},{100,100}}
/c local resources = {}
/c for _, e in pairs(game.surfaces[1].find_entities_filtered{type="resource", area=area}) do
    resources[e.name] = (resources[e.name] or 0) + e.amount
end
/c for name, amount in pairs(resources) do rcon.print(name .. ": " .. amount) end
```

## References

- [Factorio Lua API](https://lua-api.factorio.com/latest/)
- [LuaGameScript](https://lua-api.factorio.com/latest/classes/LuaGameScript.html)
- [LuaSurface](https://lua-api.factorio.com/latest/classes/LuaSurface.html)
- [LuaEntity](https://lua-api.factorio.com/latest/classes/LuaEntity.html)
