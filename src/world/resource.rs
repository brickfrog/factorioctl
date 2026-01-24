//! Resource patch types

use serde::{Deserialize, Serialize};

use super::{Area, Position};

/// A resource patch (aggregated resource tiles)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourcePatch {
    /// Resource name (e.g., "iron-ore", "copper-ore", "coal", "stone")
    pub name: String,

    /// Total amount of resource in the patch
    pub total_amount: u64,

    /// Number of resource tiles
    #[serde(default)]
    pub tile_count: u32,

    /// Center of the patch
    pub center: Position,

    /// Bounding box of the patch
    pub bounding_box: Area,
}

impl ResourcePatch {
    /// Get the approximate area of the patch
    pub fn area(&self) -> f64 {
        self.bounding_box.width() * self.bounding_box.height()
    }

    /// Get average resource per tile
    pub fn avg_per_tile(&self) -> f64 {
        if self.tile_count > 0 {
            self.total_amount as f64 / self.tile_count as f64
        } else {
            0.0
        }
    }
}

/// Common resource types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceType {
    IronOre,
    CopperOre,
    Coal,
    Stone,
    UraniumOre,
    CrudeOil,
}

impl ResourceType {
    /// Get the Factorio entity name for this resource
    pub fn name(&self) -> &'static str {
        match self {
            ResourceType::IronOre => "iron-ore",
            ResourceType::CopperOre => "copper-ore",
            ResourceType::Coal => "coal",
            ResourceType::Stone => "stone",
            ResourceType::UraniumOre => "uranium-ore",
            ResourceType::CrudeOil => "crude-oil",
        }
    }

    /// Parse from string
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "iron-ore" => Some(ResourceType::IronOre),
            "copper-ore" => Some(ResourceType::CopperOre),
            "coal" => Some(ResourceType::Coal),
            "stone" => Some(ResourceType::Stone),
            "uranium-ore" => Some(ResourceType::UraniumOre),
            "crude-oil" => Some(ResourceType::CrudeOil),
            _ => None,
        }
    }
}
