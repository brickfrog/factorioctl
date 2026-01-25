//! ASCII map rendering command

use anyhow::Result;
use clap::Parser;
use std::collections::HashMap;

use crate::cli::ResolvedConnectionArgs;
use crate::client::FactorioClient;
use crate::world::{Area, Entity, Position, TilePos};

/// Execute the map command
pub async fn execute(cmd: MapCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;
    cmd.run(&mut client).await
}

/// Render ASCII map of an area
#[derive(Parser, Debug)]
pub struct MapCommand {
    /// Center X tile coordinate (default: character position)
    #[arg(long, allow_hyphen_values = true)]
    pub x: Option<i32>,

    /// Center Y tile coordinate (default: character position)
    #[arg(long, allow_hyphen_values = true)]
    pub y: Option<i32>,

    /// Map radius (tiles from center)
    #[arg(short, long, default_value = "15")]
    pub radius: u32,

    /// Show resources
    #[arg(long, default_value = "true")]
    pub resources: bool,

    /// Detail level: minimal, normal, detailed
    #[arg(long, default_value = "normal")]
    pub detail: DetailLevel,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, clap::ValueEnum)]
pub enum DetailLevel {
    /// Only show player-built entities
    Minimal,
    /// Show entities and resources
    #[default]
    Normal,
    /// Show everything including terrain features
    Detailed,
}

impl MapCommand {
    pub async fn run(&self, client: &mut FactorioClient) -> Result<()> {
        // Get center position
        let center = if let (Some(x), Some(y)) = (self.x, self.y) {
            // Use tile center for integer coordinates
            TilePos::new(x, y).to_world_1x1()
        } else {
            client.get_character_position().await?
        };

        let r = self.radius as f64;
        let area = Area {
            left_top: Position {
                x: center.x - r,
                y: center.y - r,
            },
            right_bottom: Position {
                x: center.x + r,
                y: center.y + r,
            },
        };

        // Query entities in the area
        let entities = client.find_entities(area, None, None).await?;

        // Get character position for marking
        let char_pos = client.get_character_position().await.ok();

        // Render the map
        let map = render_ascii_map(&entities, &center, self.radius, char_pos.as_ref(), self.detail);
        println!("{}", map);

        Ok(())
    }
}

/// Character used to represent an entity on the map
fn entity_char(entity: &Entity, detail: DetailLevel) -> Option<char> {
    let name = entity.name.as_str();
    let entity_type = entity.entity_type.as_deref().unwrap_or("");

    // Skip certain entities based on detail level
    match detail {
        DetailLevel::Minimal => {
            // Only show player-built entities
            if entity.force.as_deref() != Some("player") {
                return None;
            }
        }
        DetailLevel::Normal => {
            // Skip trees and decoratives
            if entity_type == "tree" || entity_type == "decorative" {
                return None;
            }
        }
        DetailLevel::Detailed => {
            // Show everything
        }
    }

    // Resources
    if entity_type == "resource" {
        return match name {
            "iron-ore" => Some('I'),
            "copper-ore" => Some('C'),
            "coal" => Some('c'),
            "stone" => Some('S'),
            "uranium-ore" => Some('U'),
            "crude-oil" => Some('O'),
            _ => Some('?'),
        };
    }

    // Trees
    if entity_type == "tree" {
        return Some('T');
    }

    // Belts - use direction arrows
    if name == "transport-belt" || name.ends_with("-transport-belt") {
        return Some(direction_arrow(entity.direction));
    }

    // Underground belts
    if name.contains("underground-belt") {
        return Some('u');
    }

    // Splitters
    if name.contains("splitter") {
        return Some('=');
    }

    // Inserters
    if name.contains("inserter") {
        // Show direction with special chars
        return Some(match entity.direction {
            0 => '↑',  // North
            4 => '→',  // East
            8 => '↓',  // South
            12 => '←', // West
            _ => 'i',
        });
    }

    // Mining drills
    if entity_type == "mining-drill" || name.contains("mining-drill") {
        return Some('D');
    }

    // Furnaces
    if entity_type == "furnace" || name.contains("furnace") {
        return Some('F');
    }

    // Assemblers
    if name.contains("assembling-machine") {
        return Some('A');
    }

    // Containers/chests
    if entity_type == "container" || name.contains("chest") {
        return Some('B'); // Box
    }

    // Power poles
    if name.contains("pole") {
        return Some('P');
    }

    // Pipes
    if entity_type == "pipe" || name == "pipe" {
        return Some('+');
    }
    if name.contains("pipe-to-ground") {
        return Some('p');
    }

    // Walls
    if name.contains("wall") {
        return Some('#');
    }

    // Labs
    if name.contains("lab") {
        return Some('L');
    }

    // Rocks
    if name.contains("rock") {
        return Some('o');
    }

    // Default - show first letter
    Some(name.chars().next().unwrap_or('?'))
}

/// Get arrow character for belt direction
fn direction_arrow(direction: u8) -> char {
    match direction {
        0 => '^',  // North
        4 => '>',  // East
        8 => 'v',  // South
        12 => '<', // West
        _ => '-',
    }
}

/// Render entities as ASCII map
fn render_ascii_map(
    entities: &[Entity],
    center: &Position,
    radius: u32,
    char_pos: Option<&Position>,
    detail: DetailLevel,
) -> String {
    let r = radius as i32;
    let width = (radius * 2 + 1) as usize;
    let height = (radius * 2 + 1) as usize;

    // Create grid initialized with dots
    let mut grid: Vec<Vec<char>> = vec![vec!['.'; width]; height];

    // Place entities on grid
    // Group entities by integer position to handle overlaps
    let mut position_entities: HashMap<(i32, i32), Vec<&Entity>> = HashMap::new();

    for entity in entities {
        let grid_x = (entity.position.x - center.x).round() as i32 + r;
        let grid_y = (entity.position.y - center.y).round() as i32 + r;

        if grid_x >= 0 && grid_x < width as i32 && grid_y >= 0 && grid_y < height as i32 {
            position_entities
                .entry((grid_x, grid_y))
                .or_default()
                .push(entity);
        }
    }

    // Render entities with priority (player entities > resources > others)
    for ((gx, gy), ents) in position_entities {
        // Sort by priority: player entities first, then by type
        let mut sorted = ents;
        sorted.sort_by(|a, b| {
            let a_player = a.force.as_deref() == Some("player");
            let b_player = b.force.as_deref() == Some("player");
            b_player.cmp(&a_player)
        });

        if let Some(entity) = sorted.first() {
            if let Some(ch) = entity_char(entity, detail) {
                grid[gy as usize][gx as usize] = ch;
            }
        }
    }

    // Mark character position
    if let Some(pos) = char_pos {
        let cx = (pos.x - center.x).round() as i32 + r;
        let cy = (pos.y - center.y).round() as i32 + r;
        if cx >= 0 && cx < width as i32 && cy >= 0 && cy < height as i32 {
            grid[cy as usize][cx as usize] = '@';
        }
    }

    // Build output string
    let mut output = String::new();

    // Header with coordinates
    let x_min = center.x as i32 - r;
    let x_max = center.x as i32 + r;
    let y_min = center.y as i32 - r;

    output.push_str(&format!(
        "Map: ({},{}) to ({},{})\n",
        x_min, y_min, x_max, center.y as i32 + r
    ));

    // Legend
    output.push_str("Legend: @=you ^v<>=belt D=drill F=furnace i=inserter\n");
    output.push_str("        I=iron C=copper c=coal S=stone B=chest\n\n");

    // X-axis labels (every 5 tiles)
    output.push_str("    ");
    for x in 0..width {
        let abs_x = x_min + x as i32;
        if abs_x % 5 == 0 {
            output.push_str(&format!("{:<5}", abs_x));
        }
    }
    output.push('\n');

    // Grid with Y-axis labels
    for (y, row) in grid.iter().enumerate() {
        let abs_y = y_min + y as i32;
        // Y-axis label
        output.push_str(&format!("{:>3} ", abs_y));

        // Row content
        for ch in row {
            output.push(*ch);
        }
        output.push('\n');
    }

    output
}
