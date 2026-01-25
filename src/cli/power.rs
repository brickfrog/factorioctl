//! Power infrastructure commands

use anyhow::Result;
use clap::{Args, Subcommand};

use super::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::world::{Position, TilePos};

#[derive(Args, Debug)]
pub struct PowerCommand {
    #[command(subcommand)]
    pub command: PowerSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum PowerSubcommand {
    /// Run a power line from one position to another
    Line {
        /// Starting tile position (x,y as integers)
        #[arg(long, allow_hyphen_values = true)]
        from: String,

        /// Ending tile position (x,y as integers)
        #[arg(long, allow_hyphen_values = true)]
        to: String,

        /// Pole type (small-electric-pole, medium-electric-pole, big-electric-pole)
        #[arg(long, default_value = "small-electric-pole")]
        pole: String,
    },

    /// Show power network status at a position
    Status {
        /// Tile position to check (x,y as integers)
        #[arg(allow_hyphen_values = true)]
        at: String,
    },
}

pub async fn execute(cmd: PowerCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    match cmd.command {
        PowerSubcommand::Line { from, to, pole } => {
            let from_tile = parse_tile(&from)?;
            let to_tile = parse_tile(&to)?;
            // Poles are 1x1, use tile center
            let from_pos = from_tile.to_world_1x1();
            let to_pos = to_tile.to_world_1x1();

            // Get pole wire reach distance
            let spacing = get_pole_spacing(&pole);

            // Calculate total distance
            let dx = to_pos.x - from_pos.x;
            let dy = to_pos.y - from_pos.y;
            let total_dist = (dx * dx + dy * dy).sqrt();
            let num_poles = (total_dist / spacing).ceil() as i32 + 1;

            println!(
                "Running power line from ({:.0},{:.0}) to ({:.0},{:.0})",
                from_pos.x, from_pos.y, to_pos.x, to_pos.y
            );
            println!(
                "Using {} with {:.1} tile spacing, ~{} poles needed",
                pole, spacing, num_poles
            );

            let mut placed = 0;
            let mut failed = 0;

            for i in 0..num_poles {
                let t = i as f64 / (num_poles - 1).max(1) as f64;
                let x = from_pos.x + dx * t;
                let y = from_pos.y + dy * t;
                let target = Position { x, y };

                // Walk to position
                let walk_result = client.walk_to(target, false).await?;
                if !walk_result.arrived && walk_result.final_position.distance(&target) > 10.0 {
                    println!(
                        "  Couldn't reach ({:.0},{:.0}) - blocked",
                        target.x, target.y
                    );
                    failed += 1;
                    continue;
                }

                // Try to place pole
                match client
                    .place_entity(&pole, target, crate::world::Direction::North)
                    .await
                {
                    Ok(entity) => {
                        println!(
                            "  Placed {} at ({:.0},{:.0})",
                            pole, entity.position.x, entity.position.y
                        );
                        placed += 1;
                    }
                    Err(e) => {
                        // Try nearby positions
                        let mut placed_nearby = false;
                        for offset in &[(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                            let alt_pos = Position {
                                x: target.x + offset.0,
                                y: target.y + offset.1,
                            };
                            if let Ok(entity) = client
                                .place_entity(&pole, alt_pos, crate::world::Direction::North)
                                .await
                            {
                                println!(
                                    "  Placed {} at ({:.0},{:.0})",
                                    pole, entity.position.x, entity.position.y
                                );
                                placed += 1;
                                placed_nearby = true;
                                break;
                            }
                        }
                        if !placed_nearby {
                            println!("  Failed at ({:.0},{:.0}): {}", target.x, target.y, e);
                            failed += 1;
                        }
                    }
                }
            }

            println!("\nPlaced {} poles, {} failed", placed, failed);
        }

        PowerSubcommand::Status { at } => {
            let tile = parse_tile(&at)?;
            let pos = tile.to_world_1x1();

            let lua = format!(
                r#"
local surface = game.surfaces[1]
local poles = surface.find_entities_filtered{{
    type = "electric-pole",
    position = {{{}, {}}},
    radius = 50
}}
if #poles == 0 then
    rcon.print("No electric poles within 50 tiles")
else
    local nearest = poles[1]
    local network = nearest.electric_network_id
    local stats = nearest.electric_network_statistics
    rcon.print("Nearest pole: " .. nearest.name .. " at " .. nearest.position.x .. "," .. nearest.position.y)
    rcon.print("Network ID: " .. (network or "none"))
    if stats then
        rcon.print("Input: " .. (stats.input_counts and "tracked" or "not tracked"))
    end
end
"#,
                pos.x, pos.y
            );
            let response = client.execute_lua(&lua).await?;
            println!("{}", response);
        }
    }

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

fn get_pole_spacing(pole_type: &str) -> f64 {
    match pole_type {
        "small-electric-pole" => 7.0, // Wire reach is 7.5, use 7 for margin
        "medium-electric-pole" => 9.0,
        "big-electric-pole" => 28.0, // Wire reach is 30, use 28 for margin
        "substation" => 16.0,
        _ => 7.0,
    }
}
