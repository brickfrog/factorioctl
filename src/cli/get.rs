//! Query commands for game state

use anyhow::Result;
use clap::{Args, Subcommand};

use super::parsing::{parse_tile, parse_tile_area};
use super::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::output::Output;

#[derive(Args, Debug)]
pub struct GetCommand {
    #[command(subcommand)]
    pub command: GetSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum GetSubcommand {
    /// Get current game tick
    Tick,

    /// List surfaces
    Surfaces,

    /// Query entities in an area
    Entities {
        /// Area to search (x1,y1,x2,y2 as integers, inclusive)
        #[arg(long, allow_hyphen_values = true)]
        area: String,

        /// Filter by entity type
        #[arg(long, name = "type")]
        entity_type: Option<String>,

        /// Filter by entity name
        #[arg(long)]
        name: Option<String>,
    },

    /// Get a specific entity by unit number
    Entity {
        /// Entity unit number
        unit_number: u32,
    },

    /// Get an entity's inventories
    EntityInventory {
        /// Entity unit number
        unit_number: u32,
    },

    /// Query resources in an area
    Resources {
        /// Area to search (x1,y1,x2,y2 as integers, inclusive)
        #[arg(long, allow_hyphen_values = true)]
        area: Option<String>,

        /// Filter by resource type
        #[arg(long, name = "type")]
        resource_type: Option<String>,

        /// Find nearest resource from position
        #[arg(long)]
        nearest: Option<String>,

        /// Origin tile position for nearest search (x,y as integers)
        #[arg(long, allow_hyphen_values = true)]
        from: Option<String>,
    },

    /// Query tiles in an area
    Tiles {
        /// Area to search (x1,y1,x2,y2 as integers, inclusive)
        #[arg(long, allow_hyphen_values = true)]
        area: String,
    },

    /// Get a specific tile
    Tile {
        /// Tile position (x,y as integers)
        #[arg(allow_hyphen_values = true)]
        position: String,
    },

    /// Get a recipe by name
    Recipe {
        /// Recipe name (e.g., "iron-plate")
        name: Option<String>,

        /// Filter by category (e.g., "smelting")
        #[arg(long)]
        category: Option<String>,
    },

    /// Get an entity prototype
    Prototype {
        /// Entity prototype name (e.g., "stone-furnace")
        name: String,
    },

    /// Get all recipes that produce an item
    RecipesFor {
        /// Item name (e.g., "iron-plate")
        item: String,
    },
}

pub async fn execute(cmd: GetCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    match cmd.command {
        GetSubcommand::Tick => {
            let tick = client.get_tick().await?;
            Output::new(conn.output).print(&tick)?;
        }
        GetSubcommand::Surfaces => {
            let surfaces = client.get_surfaces().await?;
            Output::new(conn.output).print(&surfaces)?;
        }
        GetSubcommand::Entities {
            area,
            entity_type,
            name,
        } => {
            let tile_area = parse_tile_area(&area)?;
            let world_area = tile_area.to_world();
            let entities = client
                .find_entities(world_area, entity_type.as_deref(), name.as_deref())
                .await?;
            Output::new(conn.output).print(&entities)?;
        }
        GetSubcommand::Entity { unit_number } => {
            let entity = client.get_entity(unit_number).await?;
            Output::new(conn.output).print(&entity)?;
        }
        GetSubcommand::EntityInventory { unit_number } => {
            let inv = client.get_entity_inventory(unit_number).await?;
            println!("{}", serde_json::to_string_pretty(&inv)?);
        }
        GetSubcommand::Resources {
            area,
            resource_type,
            nearest,
            from,
        } => {
            if let (Some(resource_name), Some(from_pos)) = (nearest, from) {
                let tile = parse_tile(&from_pos)?;
                let pos = tile.to_world_1x1();
                let resource = client.find_nearest_resource(&resource_name, pos).await?;
                Output::new(conn.output).print(&resource)?;
            } else if let Some(area_str) = area {
                let tile_area = parse_tile_area(&area_str)?;
                let world_area = tile_area.to_world();
                let resources = client
                    .find_resources(world_area, resource_type.as_deref())
                    .await?;
                Output::new(conn.output).print(&resources)?;
            } else {
                anyhow::bail!("Either --area or --nearest with --from must be specified");
            }
        }
        GetSubcommand::Tiles { area } => {
            let tile_area = parse_tile_area(&area)?;
            let world_area = tile_area.to_world();
            let tiles = client.get_tiles(world_area).await?;
            Output::new(conn.output).print(&tiles)?;
        }
        GetSubcommand::Tile { position } => {
            let tile = parse_tile(&position)?;
            let pos = tile.to_world_1x1();
            let tile_result = client.get_tile(pos).await?;
            Output::new(conn.output).print(&tile_result)?;
        }
        GetSubcommand::Recipe { name, category } => {
            if let Some(recipe_name) = name {
                let recipe = client.get_recipe(&recipe_name).await?;
                Output::new(conn.output).print(&recipe)?;
            } else if let Some(cat) = category {
                let recipes = client.get_recipes_by_category(&cat).await?;
                Output::new(conn.output).print(&recipes)?;
            } else {
                anyhow::bail!("Either recipe name or --category must be specified");
            }
        }
        GetSubcommand::Prototype { name } => {
            let prototype = client.get_prototype(&name).await?;
            Output::new(conn.output).print(&prototype)?;
        }
        GetSubcommand::RecipesFor { item } => {
            let recipes = client.get_recipes_for_item(&item).await?;
            Output::new(conn.output).print(&recipes)?;
        }
    }

    client.close().await?;
    Ok(())
}

