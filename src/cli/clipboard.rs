//! Copy/paste commands using the blueprint system

use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

use crate::cli::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::world::{Area, Blueprint, BlueprintEntity, Position};

/// Default clipboard file location
fn default_clipboard_path() -> PathBuf {
    // Use home directory or current directory
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
        .join(".factorioctl-clipboard.json")
}

/// Clipboard commands for copy/paste operations
#[derive(Parser, Debug)]
pub struct ClipboardCommand {
    #[command(subcommand)]
    pub subcommand: ClipboardSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum ClipboardSubcommand {
    /// Show current clipboard contents
    Show,

    /// Clear the clipboard
    Clear,
}

/// Copy command
#[derive(Parser, Debug)]
pub struct CopyCommand {
    /// Area to copy (x1,y1,x2,y2)
    #[arg(long, allow_hyphen_values = true)]
    pub area: String,

    /// Origin point for the copy (x,y) - positions will be relative to this
    /// If not specified, uses the center of the area
    #[arg(long, allow_hyphen_values = true)]
    pub origin: Option<String>,

    /// Save to a specific file instead of clipboard
    #[arg(long)]
    pub to: Option<PathBuf>,

    /// Name for the copied blueprint
    #[arg(long, default_value = "copied")]
    pub name: String,
}

/// Paste command
#[derive(Parser, Debug)]
pub struct PasteCommand {
    /// Position to paste at (x,y) - this becomes the new origin
    #[arg(long, allow_hyphen_values = true)]
    pub at: String,

    /// Load from a specific file instead of clipboard
    #[arg(long)]
    pub from: Option<PathBuf>,

    /// Place as ghosts instead of real entities
    #[arg(long)]
    pub ghosts: bool,

    /// Dry run - show what would be placed
    #[arg(long)]
    pub dry_run: bool,
}

pub async fn execute_clipboard(cmd: ClipboardCommand, _conn: &ResolvedConnectionArgs) -> Result<()> {
    match cmd.subcommand {
        ClipboardSubcommand::Show => {
            let path = default_clipboard_path();
            if path.exists() {
                let content = std::fs::read_to_string(&path)?;
                let blueprint: Blueprint = serde_json::from_str(&content)?;
                println!("Clipboard: {}", blueprint.name);
                println!("Origin: ({}, {})", blueprint.origin[0], blueprint.origin[1]);
                println!("Entities: {}", blueprint.entities.len());
                for e in &blueprint.entities {
                    println!(
                        "  {} at ({}, {}) facing {}",
                        e.name, e.pos[0], e.pos[1], e.dir
                    );
                }
            } else {
                println!("Clipboard is empty");
            }
        }
        ClipboardSubcommand::Clear => {
            let path = default_clipboard_path();
            if path.exists() {
                std::fs::remove_file(&path)?;
                println!("Clipboard cleared");
            } else {
                println!("Clipboard was already empty");
            }
        }
    }
    Ok(())
}

pub async fn execute_copy(cmd: CopyCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    let area = parse_area(&cmd.area)?;
    let origin = if let Some(o) = &cmd.origin {
        parse_position(o)?
    } else {
        // Default to area center
        Position {
            x: (area.left_top.x + area.right_bottom.x) / 2.0,
            y: (area.left_top.y + area.right_bottom.y) / 2.0,
        }
    };

    // Get entities in area
    let entities = client.find_entities(area.clone(), None, None).await?;
    let entities: Vec<_> = entities
        .into_iter()
        .filter(|e| {
            e.force.as_deref() == Some("player")
                && e.unit_number.is_some()
                && e.name != "character"
        })
        .collect();

    if entities.is_empty() {
        println!("No entities found in area");
        client.close().await?;
        return Ok(());
    }

    // Convert to blueprint
    let bp_entities: Vec<BlueprintEntity> = entities
        .iter()
        .map(|e| BlueprintEntity {
            name: e.name.clone(),
            pos: [e.position.x - origin.x, e.position.y - origin.y],
            dir: direction_short_name(e.direction),
        })
        .collect();

    let blueprint = Blueprint {
        name: cmd.name,
        origin: [origin.x, origin.y],
        entities: bp_entities,
    };

    // Save to file
    let path = cmd.to.unwrap_or_else(default_clipboard_path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(&blueprint)?;
    std::fs::write(&path, &json)?;

    println!("Copied {} entities to {}", blueprint.entities.len(), path.display());
    println!("Origin: ({}, {})", origin.x, origin.y);
    for e in &blueprint.entities {
        println!(
            "  {} at ({}, {}) facing {}",
            e.name, e.pos[0], e.pos[1], e.dir
        );
    }

    client.close().await?;
    Ok(())
}

pub async fn execute_paste(cmd: PasteCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    // Load blueprint
    let path = cmd.from.unwrap_or_else(default_clipboard_path);
    if !path.exists() {
        anyhow::bail!("Clipboard is empty (no file at {})", path.display());
    }
    let content = std::fs::read_to_string(&path)?;
    let blueprint: Blueprint = serde_json::from_str(&content)?;

    // Parse target position
    let target = parse_position(&cmd.at)?;

    println!(
        "Pasting {} entities at ({}, {})",
        blueprint.entities.len(),
        target.x,
        target.y
    );

    if cmd.dry_run {
        println!("\nDry run - would place:");
        for e in &blueprint.entities {
            let abs_x = target.x + e.pos[0];
            let abs_y = target.y + e.pos[1];
            let entity_type = if cmd.ghosts { "ghost" } else { "entity" };
            println!(
                "  {} {} at ({:.1}, {:.1}) facing {}",
                entity_type, e.name, abs_x, abs_y, e.dir
            );
        }
        client.close().await?;
        return Ok(());
    }

    // Place entities
    let mut placed = 0;
    let mut errors = Vec::new();

    for e in &blueprint.entities {
        let abs_pos = Position {
            x: target.x + e.pos[0],
            y: target.y + e.pos[1],
        };
        let direction = e.direction();

        let result = if cmd.ghosts {
            client.place_ghost(&e.name, abs_pos, direction).await
        } else {
            client.place_entity(&e.name, abs_pos, direction).await
        };

        match result {
            Ok(entity) => {
                placed += 1;
                let entity_type = if cmd.ghosts { "ghost" } else { "" };
                println!(
                    "  Placed {} {} #{} at ({:.1}, {:.1})",
                    entity_type,
                    entity.name,
                    entity.unit_number.unwrap_or(0),
                    entity.position.x,
                    entity.position.y
                );
            }
            Err(e) => {
                errors.push(format!(
                    "Failed to place {} at ({:.1}, {:.1}): {}",
                    e, abs_pos.x, abs_pos.y, e
                ));
            }
        }
    }

    println!(
        "\nPlaced {}/{} entities",
        placed,
        blueprint.entities.len()
    );
    if !errors.is_empty() {
        println!("Errors:");
        for err in &errors {
            println!("  {}", err);
        }
    }

    client.close().await?;
    Ok(())
}

fn parse_area(s: &str) -> Result<Area> {
    let parts: Vec<f64> = s
        .split(',')
        .map(|p| p.trim().parse())
        .collect::<Result<_, _>>()?;
    if parts.len() != 4 {
        anyhow::bail!("Area must be x1,y1,x2,y2");
    }
    Ok(Area {
        left_top: Position {
            x: parts[0],
            y: parts[1],
        },
        right_bottom: Position {
            x: parts[2],
            y: parts[3],
        },
    })
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

fn direction_short_name(dir: u8) -> String {
    match dir {
        0 => "n",
        2 => "ne",
        4 => "e",
        6 => "se",
        8 => "s",
        10 => "sw",
        12 => "w",
        14 => "nw",
        _ => "n",
    }
    .to_string()
}
