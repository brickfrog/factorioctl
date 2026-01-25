//! Entity placement commands

use anyhow::Result;
use clap::Args;

use super::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::output::Output;
use crate::world::{entity_size, Direction, TilePos};

#[derive(Args, Debug)]
pub struct PlaceCommand {
    /// Entity name to place
    pub entity_name: String,

    /// Tile position to place at (x,y as integers)
    #[arg(long, allow_hyphen_values = true)]
    pub at: String,

    /// Direction (n, e, s, w, or 0-7)
    #[arg(long, default_value = "n")]
    pub direction: String,
}

pub async fn execute(cmd: PlaceCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    let tile = parse_tile(&cmd.at)?;
    let dir = parse_direction(&cmd.direction)?;

    // Get entity size and compute world position (center of entity)
    let (width, height) = entity_size(&cmd.entity_name);
    let world_pos = tile.to_world(width, height);

    // Check proximity before placing
    client
        .ensure_proximity_to_position(world_pos, crate::client::PROXIMITY_RANGE_PLACE)
        .await?;

    let entity = client.place_entity(&cmd.entity_name, world_pos, dir).await?;
    Output::new(conn.output).print(&entity)?;

    client.close().await?;
    Ok(())
}

/// Parse integer tile coordinates (x,y)
fn parse_tile(s: &str) -> Result<TilePos> {
    let parts: Vec<&str> = s.split(',').collect();
    if parts.len() != 2 {
        anyhow::bail!("Position must be x,y (integers)");
    }

    let x: i32 = parts[0]
        .trim()
        .parse()
        .map_err(|_| anyhow::anyhow!("X coordinate must be an integer, got '{}'", parts[0].trim()))?;
    let y: i32 = parts[1]
        .trim()
        .parse()
        .map_err(|_| anyhow::anyhow!("Y coordinate must be an integer, got '{}'", parts[1].trim()))?;

    Ok(TilePos::new(x, y))
}

fn parse_direction(s: &str) -> Result<Direction> {
    match s.to_lowercase().as_str() {
        "n" | "north" | "0" => Ok(Direction::North),
        "ne" | "northeast" | "1" => Ok(Direction::NorthEast),
        "e" | "east" | "2" => Ok(Direction::East),
        "se" | "southeast" | "3" => Ok(Direction::SouthEast),
        "s" | "south" | "4" => Ok(Direction::South),
        "sw" | "southwest" | "5" => Ok(Direction::SouthWest),
        "w" | "west" | "6" => Ok(Direction::West),
        "nw" | "northwest" | "7" => Ok(Direction::NorthWest),
        _ => anyhow::bail!("Invalid direction: {}", s),
    }
}
