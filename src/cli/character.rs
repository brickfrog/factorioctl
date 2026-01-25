//! Character control commands

use anyhow::Result;
use clap::{Args, Subcommand};

use super::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::output::Output;
use crate::world::{Position, TilePos};

#[derive(Args, Debug)]
pub struct CharacterCommand {
    #[command(subcommand)]
    pub command: CharacterSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum CharacterSubcommand {
    /// Initialize/create character at spawn
    Init,

    /// Teleport character to position (debug command, accepts floats)
    Teleport {
        /// Target position (x,y as floats)
        #[arg(allow_hyphen_values = true)]
        position: String,
    },

    /// Walk character to position
    Walk {
        /// Target tile position (x,y as integers)
        #[arg(long, allow_hyphen_values = true)]
        to: String,
    },

    /// Get character status
    Status,

    /// Get character inventory
    Inventory,
}

pub async fn execute(cmd: CharacterCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    match cmd.command {
        CharacterSubcommand::Init => {
            let character = client.init_character().await?;
            Output::new(conn.output).print(&character)?;
        }
        CharacterSubcommand::Teleport { position } => {
            let pos = parse_position(&position)?;
            client.teleport_character(pos).await?;
            println!("Teleported to ({}, {})", pos.x, pos.y);
        }
        CharacterSubcommand::Walk { to } => {
            let tile = parse_tile(&to)?;
            let pos = tile.to_world_1x1();
            client.walk_character(pos).await?;
            println!("Walking to tile ({}, {})", tile.x, tile.y);
        }
        CharacterSubcommand::Status => {
            let status = client.character_status().await?;
            Output::new(conn.output).print(&status)?;
        }
        CharacterSubcommand::Inventory => {
            let inventory = client.character_inventory().await?;
            Output::new(conn.output).print(&inventory)?;
        }
    }

    client.close().await?;
    Ok(())
}

fn parse_position(s: &str) -> Result<Position> {
    let parts: Vec<f64> = s
        .split(',')
        .map(|p| p.trim().parse())
        .collect::<Result<_, _>>()?;
    if parts.len() != 2 {
        anyhow::bail!("Position must be x,y");
    }
    Ok(Position {
        x: parts[0],
        y: parts[1],
    })
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
