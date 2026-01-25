//! Entity prototype types for Factorio

use serde::{Deserialize, Serialize};

/// Entity prototype data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prototype {
    /// Entity name (e.g., "stone-furnace")
    pub name: String,
    /// Entity type (e.g., "furnace", "mining-drill", "assembling-machine")
    #[serde(rename = "type")]
    pub entity_type: String,
    /// Collision box size [width, height]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<[f64; 2]>,

    // Crafting machine properties
    /// Crafting speed multiplier (1.0 = normal)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub crafting_speed: Option<f64>,
    /// Categories this machine can craft
    #[serde(skip_serializing_if = "Option::is_none")]
    pub crafting_categories: Option<Vec<String>>,

    // Mining drill properties
    /// Mining speed
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mining_speed: Option<f64>,
    /// Mining power (affects what can be mined)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mining_power: Option<f64>,
    /// Resource categories this drill can mine
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resource_categories: Option<Vec<String>>,

    // Inserter properties
    /// Inserter rotation speed
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rotation_speed: Option<f64>,
    /// Inserter extension speed
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extension_speed: Option<f64>,

    // Energy properties
    /// Energy source type: "burner", "electric", "heat", "void"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub energy_source: Option<String>,
    /// Energy usage in watts (for electric entities)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub energy_usage: Option<f64>,

    // Belt properties
    /// Belt speed (items per second)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub belt_speed: Option<f64>,
}

impl Prototype {
    /// Check if this is a crafting machine (furnace, assembler, etc.)
    pub fn is_crafting_machine(&self) -> bool {
        self.crafting_speed.is_some()
    }

    /// Check if this is a mining drill
    pub fn is_mining_drill(&self) -> bool {
        self.mining_speed.is_some()
    }

    /// Check if this is an inserter
    pub fn is_inserter(&self) -> bool {
        self.entity_type == "inserter"
    }

    /// Check if this is a transport belt
    pub fn is_belt(&self) -> bool {
        self.entity_type == "transport-belt"
    }

    /// Get the approximate tile size (rounded up from collision box)
    pub fn tile_size(&self) -> [u32; 2] {
        match &self.size {
            Some([w, h]) => [w.ceil() as u32, h.ceil() as u32],
            None => [1, 1],
        }
    }
}
