//! Tile (terrain) types

use serde::{Deserialize, Serialize};

use super::Position;

/// A terrain tile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tile {
    /// Tile name (e.g., "grass-1", "water", "concrete")
    pub name: String,

    /// Tile position
    pub position: Position,

    /// Whether this tile collides with player movement
    #[serde(default)]
    pub collides_with_player: bool,
}

impl Tile {
    /// Check if this is a water tile
    pub fn is_water(&self) -> bool {
        self.name.contains("water") || self.name.contains("deepwater")
    }

    /// Check if this is a walkable tile
    pub fn is_walkable(&self) -> bool {
        !self.collides_with_player
    }
}

/// Common tile types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TileType {
    Grass,
    Sand,
    Dirt,
    Water,
    DeepWater,
    Concrete,
    Stone,
}

impl TileType {
    /// Check if this tile type blocks movement
    pub fn blocks_movement(&self) -> bool {
        matches!(self, TileType::Water | TileType::DeepWater)
    }
}
