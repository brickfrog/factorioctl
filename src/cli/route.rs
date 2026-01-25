//! Route command for pathfinding belt routes

use anyhow::Result;
use clap::{Args, Subcommand};

use super::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::world::{find_belt_route, Area, GridPos, Position};

#[derive(Args, Debug)]
pub struct RouteCommand {
    #[command(subcommand)]
    pub subcommand: RouteSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum RouteSubcommand {
    /// Route transport belts from point A to point B
    Belt {
        /// Starting position (x,y)
        #[arg(long, allow_hyphen_values = true)]
        from: String,

        /// Ending position (x,y)
        #[arg(long, allow_hyphen_values = true)]
        to: String,

        /// Belt type to use
        #[arg(long, default_value = "transport-belt")]
        belt_type: String,

        /// Search radius for obstacle detection (tiles from path bounds)
        #[arg(long, default_value = "10")]
        search_radius: u32,

        /// Dry run - show route without placing
        #[arg(long)]
        dry_run: bool,

        /// Output route as JSON (for piping to other commands)
        #[arg(long)]
        plan_only: bool,
    },
}

pub async fn execute(cmd: RouteCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    match cmd.subcommand {
        RouteSubcommand::Belt {
            from,
            to,
            belt_type,
            search_radius,
            dry_run,
            plan_only,
        } => {
            let start = parse_position(&from)?;
            let end = parse_position(&to)?;

            // Calculate search area (bounding box of path + radius padding)
            let area = calculate_search_area(&start, &end, search_radius);

            println!(
                "Finding route from ({}, {}) to ({}, {})",
                start.x, start.y, end.x, end.y
            );
            println!(
                "Search area: ({}, {}) to ({}, {})",
                area.left_top.x, area.left_top.y, area.right_bottom.x, area.right_bottom.y
            );

            // Build collision map
            let collision_map = client.build_collision_map(area).await?;
            println!("Collision map: {} blocked tiles", collision_map.blocked_count());

            // Find path
            let start_grid = GridPos::from_position(&start);
            let end_grid = GridPos::from_position(&end);
            let result = find_belt_route(start_grid, end_grid, &collision_map);

            if plan_only {
                // Output as JSON
                println!("{}", serde_json::to_string_pretty(&result)?);
                client.close().await?;
                return Ok(());
            }

            if !result.success {
                println!("Route failed: {}", result.error.as_deref().unwrap_or("unknown"));
                client.close().await?;
                return Ok(());
            }

            println!(
                "Found route: {} belts, {} turns",
                result.belt_count, result.turn_count
            );

            if dry_run {
                println!("\nDry run - would place:");
                for belt in &result.belts {
                    println!(
                        "  {} at ({}, {}) facing {:?}",
                        belt_type, belt.position.x, belt.position.y, belt.direction
                    );
                }
                client.close().await?;
                return Ok(());
            }

            // Place the belts
            println!("\nPlacing belts...");
            let mut placed = 0;
            let mut errors = Vec::new();

            for belt in &result.belts {
                match client
                    .place_entity(&belt_type, belt.position, belt.direction)
                    .await
                {
                    Ok(entity) => {
                        placed += 1;
                        println!(
                            "  Placed {} #{} at ({}, {})",
                            belt_type,
                            entity.unit_number.unwrap_or(0),
                            entity.position.x,
                            entity.position.y
                        );
                    }
                    Err(e) => {
                        errors.push(format!(
                            "Failed at ({}, {}): {}",
                            belt.position.x, belt.position.y, e
                        ));
                    }
                }
            }

            println!("\nPlaced {}/{} belts", placed, result.belt_count);
            if !errors.is_empty() {
                println!("Errors:");
                for err in &errors {
                    println!("  {}", err);
                }
            }
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

fn calculate_search_area(start: &Position, end: &Position, padding: u32) -> Area {
    let padding = padding as f64;
    Area {
        left_top: Position {
            x: start.x.min(end.x) - padding,
            y: start.y.min(end.y) - padding,
        },
        right_bottom: Position {
            x: start.x.max(end.x) + padding,
            y: start.y.max(end.y) + padding,
        },
    }
}
