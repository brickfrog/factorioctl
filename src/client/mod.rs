//! Factorio client for communicating with the game server

pub mod lua;
pub mod rcon;
pub mod server;

use anyhow::Result;

use crate::world::{
    Area, CharacterStatus, CraftResult, Direction, Entity, Inventory, MineResult, Position,
    ResourcePatch, Surface, Tick, Tile,
};
use lua::LuaCommand;
use rcon::RconClient;

/// High-level client for interacting with Factorio
pub struct FactorioClient {
    rcon: RconClient,
}

impl FactorioClient {
    /// Connect to a Factorio server
    pub async fn connect(host: &str, port: u16, password: &str) -> Result<Self> {
        let mut rcon = RconClient::connect(host, port, password).await?;

        // Send warmup command (first command after connection may get dropped)
        let _ = rcon.execute("/c").await;

        Ok(Self { rcon })
    }

    /// Close the connection
    pub async fn close(&mut self) -> Result<()> {
        self.rcon.close().await
    }

    /// Execute a raw Lua command
    pub async fn execute_lua(&mut self, lua: &str) -> Result<String> {
        self.rcon.execute(&format!("/c {}", lua)).await
    }

    /// Execute a silent Lua command (no console output)
    pub async fn execute_lua_silent(&mut self, lua: &str) -> Result<String> {
        self.rcon.execute(&format!("/silent-command {}", lua)).await
    }

    // --- Game State Queries ---

    /// Get current game tick
    pub async fn get_tick(&mut self) -> Result<Tick> {
        let response = self.execute_lua("rcon.print(game.tick)").await?;
        let tick: u64 = response.trim().parse()?;
        Ok(Tick { tick })
    }

    /// Get list of surfaces
    pub async fn get_surfaces(&mut self) -> Result<Vec<Surface>> {
        let lua = LuaCommand::get_surfaces();
        let response = self.execute_lua(&lua).await?;
        let surfaces: Vec<Surface> = serde_json::from_str(&response)?;
        Ok(surfaces)
    }

    // --- Entity Queries ---

    /// Find entities in an area
    pub async fn find_entities(
        &mut self,
        area: Area,
        entity_type: Option<&str>,
        name: Option<&str>,
    ) -> Result<Vec<Entity>> {
        let lua = LuaCommand::find_entities(area, entity_type, name);
        let response = self.execute_lua(&lua).await?;
        let entities: Vec<Entity> = serde_json::from_str(&response)?;
        Ok(entities)
    }

    /// Get a specific entity by unit number
    pub async fn get_entity(&mut self, unit_number: u32) -> Result<Entity> {
        let lua = LuaCommand::get_entity(unit_number);
        let response = self.execute_lua(&lua).await?;
        let entity: Entity = serde_json::from_str(&response)?;
        Ok(entity)
    }

    // --- Resource Queries ---

    /// Find resources in an area
    pub async fn find_resources(
        &mut self,
        area: Area,
        resource_type: Option<&str>,
    ) -> Result<Vec<ResourcePatch>> {
        let lua = LuaCommand::find_resources(area, resource_type);
        let response = self.execute_lua(&lua).await?;
        let resources: Vec<ResourcePatch> = serde_json::from_str(&response)?;
        Ok(resources)
    }

    /// Find nearest resource from a position
    pub async fn find_nearest_resource(
        &mut self,
        resource_name: &str,
        from: Position,
    ) -> Result<ResourcePatch> {
        let lua = LuaCommand::find_nearest_resource(resource_name, from);
        let response = self.execute_lua(&lua).await?;
        let resource: ResourcePatch = serde_json::from_str(&response)?;
        Ok(resource)
    }

    // --- Tile Queries ---

    /// Get tiles in an area
    pub async fn get_tiles(&mut self, area: Area) -> Result<Vec<Tile>> {
        let lua = LuaCommand::get_tiles(area);
        let response = self.execute_lua(&lua).await?;
        let tiles: Vec<Tile> = serde_json::from_str(&response)?;
        Ok(tiles)
    }

    /// Get a specific tile
    pub async fn get_tile(&mut self, position: Position) -> Result<Tile> {
        let lua = LuaCommand::get_tile(position);
        let response = self.execute_lua(&lua).await?;
        let tile: Tile = serde_json::from_str(&response)?;
        Ok(tile)
    }

    // --- Character Control ---

    /// Initialize character entity
    pub async fn init_character(&mut self) -> Result<Entity> {
        let lua = LuaCommand::init_character();
        let response = self.execute_lua(&lua).await?;
        let entity: Entity = serde_json::from_str(&response)?;
        Ok(entity)
    }

    /// Teleport character to position
    pub async fn teleport_character(&mut self, position: Position) -> Result<()> {
        let lua = LuaCommand::teleport_character(position);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    /// Start walking character to position
    pub async fn walk_character(&mut self, position: Position) -> Result<()> {
        let lua = LuaCommand::walk_character(position);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    /// Get character status
    pub async fn character_status(&mut self) -> Result<CharacterStatus> {
        let lua = LuaCommand::character_status();
        let response = self.execute_lua(&lua).await?;
        let status: CharacterStatus = serde_json::from_str(&response)?;
        Ok(status)
    }

    /// Get character inventory
    pub async fn character_inventory(&mut self) -> Result<Inventory> {
        let lua = LuaCommand::character_inventory();
        let response = self.execute_lua(&lua).await?;
        let inventory: Inventory = serde_json::from_str(&response)?;
        Ok(inventory)
    }

    // --- Mining ---

    /// Mine entity at position
    pub async fn mine_at(&mut self, position: Position, count: u32) -> Result<MineResult> {
        let lua = LuaCommand::mine_at(position, count);
        let response = self.execute_lua(&lua).await?;
        let result: MineResult = serde_json::from_str(&response)?;
        Ok(result)
    }

    /// Mine nearest entity of type
    pub async fn mine_nearest(&mut self, entity_type: &str, count: u32) -> Result<MineResult> {
        let lua = LuaCommand::mine_nearest(entity_type, count);
        let response = self.execute_lua(&lua).await?;
        let result: MineResult = serde_json::from_str(&response)?;
        Ok(result)
    }

    // --- Crafting ---

    /// Start crafting a recipe
    pub async fn craft(&mut self, recipe: &str, count: u32) -> Result<CraftResult> {
        let lua = LuaCommand::craft(recipe, count);
        let response = self.execute_lua(&lua).await?;
        let result: CraftResult = serde_json::from_str(&response)?;
        Ok(result)
    }

    /// Wait for crafting to complete
    pub async fn wait_for_crafting(&mut self) -> Result<()> {
        let lua = LuaCommand::wait_for_crafting();
        self.execute_lua(&lua).await?;
        Ok(())
    }

    // --- Entity Actions ---

    /// Place an entity from inventory
    pub async fn place_entity(
        &mut self,
        entity_name: &str,
        position: Position,
        direction: Direction,
    ) -> Result<Entity> {
        let lua = LuaCommand::place_entity(entity_name, position, direction);
        let response = self.execute_lua(&lua).await?;
        let entity: Entity = serde_json::from_str(&response)?;
        Ok(entity)
    }

    /// Remove entity at position
    pub async fn remove_entity_at(&mut self, position: Position) -> Result<()> {
        let lua = LuaCommand::remove_entity_at(position);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    /// Remove entity by unit number
    pub async fn remove_entity(&mut self, unit_number: u32) -> Result<()> {
        let lua = LuaCommand::remove_entity(unit_number);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    /// Insert items into an entity
    pub async fn insert_items(
        &mut self,
        unit_number: u32,
        item: &str,
        count: u32,
        inventory_type: &str,
    ) -> Result<()> {
        let lua = LuaCommand::insert_items(unit_number, item, count, inventory_type);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    /// Set recipe on an assembling machine
    pub async fn set_recipe(&mut self, unit_number: u32, recipe: &str) -> Result<()> {
        let lua = LuaCommand::set_recipe(unit_number, recipe);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    // --- Tick Control ---

    /// Pause the game
    pub async fn pause_game(&mut self) -> Result<()> {
        self.execute_lua("game.tick_paused = true").await?;
        Ok(())
    }

    /// Resume the game
    pub async fn resume_game(&mut self) -> Result<()> {
        self.execute_lua("game.tick_paused = false").await?;
        Ok(())
    }

    /// Set game speed
    pub async fn set_game_speed(&mut self, speed: f64) -> Result<()> {
        let lua = format!("game.speed = {}", speed);
        self.execute_lua(&lua).await?;
        Ok(())
    }

    /// Wait for N ticks
    pub async fn wait_ticks(&mut self, ticks: u32) -> Result<()> {
        let start = self.get_tick().await?.tick;
        let target = start + ticks as u64;

        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            let current = self.get_tick().await?.tick;
            if current >= target {
                break;
            }
        }

        Ok(())
    }
}
