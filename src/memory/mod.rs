//! Spatial memory and zone management for the Factorio AI agent
//!
//! This module provides persistent memory for:
//! - Zone definitions (mining, smelting, assembly, etc.)
//! - Protected resources (ore patches that shouldn't be built on)
//! - Agent notes and observations

use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::world::{Area, Position};

/// Type of zone, defining what entities are appropriate there
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ZoneType {
    /// For miners on ore patches
    Mining,
    /// For furnace arrays
    Smelting,
    /// For assembling machines
    Assembly,
    /// For boilers, steam engines, solar
    Power,
    /// For chests and logistics
    Storage,
    /// For belt highways, main bus
    Logistics,
    /// Marked for future use, blocks all placement
    Reserved,
    /// Custom zone type
    Custom(String),
}

impl ZoneType {
    /// Get the allowed entity types for this zone
    pub fn allowed_entities(&self) -> Vec<&'static str> {
        match self {
            ZoneType::Mining => vec![
                "electric-mining-drill",
                "burner-mining-drill",
                "pumpjack",
                "transport-belt",
                "fast-transport-belt",
                "express-transport-belt",
                "underground-belt",
                "fast-underground-belt",
                "express-underground-belt",
                "inserter",
                "fast-inserter",
                "long-handed-inserter",
                "burner-inserter",
                "small-electric-pole",
                "medium-electric-pole",
                "big-electric-pole",
                "substation",
            ],
            ZoneType::Smelting => vec![
                "stone-furnace",
                "steel-furnace",
                "electric-furnace",
                "transport-belt",
                "fast-transport-belt",
                "express-transport-belt",
                "underground-belt",
                "fast-underground-belt",
                "express-underground-belt",
                "splitter",
                "fast-splitter",
                "express-splitter",
                "inserter",
                "fast-inserter",
                "long-handed-inserter",
                "burner-inserter",
                "small-electric-pole",
                "medium-electric-pole",
                "big-electric-pole",
                "substation",
                "wooden-chest",
                "iron-chest",
                "steel-chest",
            ],
            ZoneType::Assembly => vec![
                "assembling-machine-1",
                "assembling-machine-2",
                "assembling-machine-3",
                "chemical-plant",
                "oil-refinery",
                "lab",
                "transport-belt",
                "fast-transport-belt",
                "express-transport-belt",
                "underground-belt",
                "fast-underground-belt",
                "express-underground-belt",
                "splitter",
                "fast-splitter",
                "express-splitter",
                "inserter",
                "fast-inserter",
                "long-handed-inserter",
                "stack-inserter",
                "small-electric-pole",
                "medium-electric-pole",
                "big-electric-pole",
                "substation",
                "wooden-chest",
                "iron-chest",
                "steel-chest",
            ],
            ZoneType::Power => vec![
                "boiler",
                "steam-engine",
                "solar-panel",
                "accumulator",
                "offshore-pump",
                "pump",
                "pipe",
                "pipe-to-ground",
                "small-electric-pole",
                "medium-electric-pole",
                "big-electric-pole",
                "substation",
            ],
            ZoneType::Storage => vec![
                "wooden-chest",
                "iron-chest",
                "steel-chest",
                "logistic-chest-passive-provider",
                "logistic-chest-active-provider",
                "logistic-chest-storage",
                "logistic-chest-buffer",
                "logistic-chest-requester",
                "inserter",
                "fast-inserter",
                "long-handed-inserter",
                "stack-inserter",
                "small-electric-pole",
                "medium-electric-pole",
            ],
            ZoneType::Logistics => vec![
                "transport-belt",
                "fast-transport-belt",
                "express-transport-belt",
                "underground-belt",
                "fast-underground-belt",
                "express-underground-belt",
                "splitter",
                "fast-splitter",
                "express-splitter",
                "small-electric-pole",
                "medium-electric-pole",
                "big-electric-pole",
                "substation",
            ],
            ZoneType::Reserved => vec![],
            ZoneType::Custom(_) => vec![], // Allow anything in custom zones
        }
    }

    /// Check if an entity is allowed in this zone
    pub fn allows_entity(&self, entity_name: &str) -> bool {
        match self {
            ZoneType::Custom(_) => true, // Custom zones allow everything
            _ => {
                let allowed = self.allowed_entities();
                // Check for exact match or partial match (for belt variants, etc.)
                allowed.iter().any(|a| {
                    entity_name == *a
                        || entity_name.contains(a)
                        || a.contains(entity_name)
                })
            }
        }
    }
}

impl std::fmt::Display for ZoneType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ZoneType::Mining => write!(f, "mining"),
            ZoneType::Smelting => write!(f, "smelting"),
            ZoneType::Assembly => write!(f, "assembly"),
            ZoneType::Power => write!(f, "power"),
            ZoneType::Storage => write!(f, "storage"),
            ZoneType::Logistics => write!(f, "logistics"),
            ZoneType::Reserved => write!(f, "reserved"),
            ZoneType::Custom(s) => write!(f, "custom:{}", s),
        }
    }
}

/// A defined zone in the factory
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Zone {
    /// Unique identifier for this zone
    pub id: String,
    /// Type of zone (determines what can be placed here)
    pub zone_type: ZoneType,
    /// Rectangular bounds of the zone
    pub bounds: Area,
    /// Optional description or notes
    pub description: Option<String>,
    /// Game tick when this zone was created
    pub created_tick: u64,
}

impl Zone {
    /// Create a new zone
    pub fn new(id: String, zone_type: ZoneType, bounds: Area) -> Self {
        Self {
            id,
            zone_type,
            bounds,
            description: None,
            created_tick: 0,
        }
    }

    /// Check if a position is within this zone
    pub fn contains(&self, pos: &Position) -> bool {
        self.bounds.contains(pos)
    }

    /// Check if an entity is appropriate for this zone
    pub fn allows_entity(&self, entity_name: &str) -> bool {
        self.zone_type.allows_entity(entity_name)
    }
}

/// A protected resource patch (ore) that shouldn't be built on
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtectedResource {
    /// Resource type (e.g., "iron-ore", "copper-ore")
    pub resource_type: String,
    /// Bounds of the resource patch
    pub bounds: Area,
    /// Center of the resource patch
    pub center: Position,
    /// Total amount of resource in the patch
    pub total_amount: u64,
    /// Number of tiles in the patch
    pub tile_count: u32,
}

impl ProtectedResource {
    /// Check if a position overlaps with this resource
    pub fn contains(&self, pos: &Position) -> bool {
        self.bounds.contains(pos)
    }
}

/// Result of a placement check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlacementCheck {
    /// Whether placement is allowed
    pub allowed: bool,
    /// Warning messages (non-fatal)
    pub warnings: Vec<String>,
    /// Error messages (fatal, blocks placement)
    pub errors: Vec<String>,
    /// Zones that overlap with the placement
    pub overlapping_zones: Vec<String>,
    /// Protected resources that overlap
    pub overlapping_resources: Vec<String>,
}

impl PlacementCheck {
    /// Create a new check result indicating success
    pub fn ok() -> Self {
        Self {
            allowed: true,
            warnings: vec![],
            errors: vec![],
            overlapping_zones: vec![],
            overlapping_resources: vec![],
        }
    }

    /// Create a new check result with an error
    pub fn error(msg: impl Into<String>) -> Self {
        Self {
            allowed: false,
            warnings: vec![],
            errors: vec![msg.into()],
            overlapping_zones: vec![],
            overlapping_resources: vec![],
        }
    }

    /// Add a warning (doesn't block placement)
    pub fn with_warning(mut self, msg: impl Into<String>) -> Self {
        self.warnings.push(msg.into());
        self
    }

    /// Add an error (blocks placement)
    pub fn with_error(mut self, msg: impl Into<String>) -> Self {
        self.allowed = false;
        self.errors.push(msg.into());
        self
    }
}

/// Persistent agent memory
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AgentMemory {
    /// Defined zones
    pub zones: HashMap<String, Zone>,
    /// Protected resource patches
    pub protected_resources: Vec<ProtectedResource>,
    /// General notes (key-value)
    pub notes: HashMap<String, String>,
}

impl AgentMemory {
    /// Create empty memory
    pub fn new() -> Self {
        Self::default()
    }

    /// Get the default memory file path
    pub fn default_path() -> PathBuf {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(".agent_memory.json")
    }

    /// Load memory from the default path
    pub fn load() -> Self {
        Self::load_from(&Self::default_path())
    }

    /// Load memory from a specific path
    pub fn load_from(path: &PathBuf) -> Self {
        match std::fs::read_to_string(path) {
            Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
            Err(_) => Self::default(),
        }
    }

    /// Save memory to the default path
    pub fn save(&self) -> Result<(), String> {
        self.save_to(&Self::default_path())
    }

    /// Save memory to a specific path
    pub fn save_to(&self, path: &PathBuf) -> Result<(), String> {
        let content = serde_json::to_string_pretty(self)
            .map_err(|e| format!("Failed to serialize memory: {}", e))?;
        std::fs::write(path, content)
            .map_err(|e| format!("Failed to write memory file: {}", e))
    }

    // === Zone Management ===

    /// Add or update a zone
    pub fn set_zone(&mut self, zone: Zone) {
        self.zones.insert(zone.id.clone(), zone);
    }

    /// Get a zone by ID
    pub fn get_zone(&self, id: &str) -> Option<&Zone> {
        self.zones.get(id)
    }

    /// Remove a zone by ID
    pub fn remove_zone(&mut self, id: &str) -> Option<Zone> {
        self.zones.remove(id)
    }

    /// Find all zones containing a position
    pub fn zones_at(&self, pos: &Position) -> Vec<&Zone> {
        self.zones
            .values()
            .filter(|z| z.contains(pos))
            .collect()
    }

    /// Find all zones overlapping an area
    pub fn zones_overlapping(&self, area: &Area) -> Vec<&Zone> {
        self.zones
            .values()
            .filter(|z| areas_overlap(&z.bounds, area))
            .collect()
    }

    // === Resource Protection ===

    /// Add a protected resource
    pub fn add_protected_resource(&mut self, resource: ProtectedResource) {
        // Check if we already have this resource (same type and overlapping bounds)
        let exists = self.protected_resources.iter().any(|r| {
            r.resource_type == resource.resource_type
                && areas_overlap(&r.bounds, &resource.bounds)
        });

        if !exists {
            self.protected_resources.push(resource);
        }
    }

    /// Find protected resources at a position
    pub fn resources_at(&self, pos: &Position) -> Vec<&ProtectedResource> {
        self.protected_resources
            .iter()
            .filter(|r| r.contains(pos))
            .collect()
    }

    /// Find protected resources overlapping an area
    pub fn resources_overlapping(&self, area: &Area) -> Vec<&ProtectedResource> {
        self.protected_resources
            .iter()
            .filter(|r| areas_overlap(&r.bounds, area))
            .collect()
    }

    /// Clear all protected resources
    pub fn clear_protected_resources(&mut self) {
        self.protected_resources.clear();
    }

    // === Placement Validation ===

    /// Check if placing an entity at a position is appropriate
    pub fn check_placement(&self, entity_name: &str, pos: &Position) -> PlacementCheck {
        let mut result = PlacementCheck::ok();

        // Check zones
        let zones = self.zones_at(pos);
        for zone in &zones {
            result.overlapping_zones.push(zone.id.clone());

            if zone.zone_type == ZoneType::Reserved {
                result = result.with_error(format!(
                    "Position is in reserved zone '{}' - no building allowed",
                    zone.id
                ));
            } else if !zone.allows_entity(entity_name) {
                result = result.with_warning(format!(
                    "Entity '{}' may not be appropriate for {} zone '{}'",
                    entity_name, zone.zone_type, zone.id
                ));
            }
        }

        // Check protected resources
        let resources = self.resources_at(pos);
        for resource in &resources {
            result
                .overlapping_resources
                .push(resource.resource_type.clone());

            // Only miners and related infrastructure should be on resources
            let is_mining_entity = entity_name.contains("mining-drill")
                || entity_name.contains("pumpjack")
                || entity_name.contains("belt")
                || entity_name.contains("inserter")
                || entity_name.contains("pole");

            if !is_mining_entity {
                result = result.with_error(format!(
                    "Position overlaps {} resource - use this area for mining only!",
                    resource.resource_type
                ));
            }
        }

        result
    }

    // === Notes ===

    /// Set a note
    pub fn set_note(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.notes.insert(key.into(), value.into());
    }

    /// Get a note
    pub fn get_note(&self, key: &str) -> Option<&String> {
        self.notes.get(key)
    }

    /// Remove a note
    pub fn remove_note(&mut self, key: &str) -> Option<String> {
        self.notes.remove(key)
    }
}

/// Check if two areas overlap
fn areas_overlap(a: &Area, b: &Area) -> bool {
    a.left_top.x < b.right_bottom.x
        && a.right_bottom.x > b.left_top.x
        && a.left_top.y < b.right_bottom.y
        && a.right_bottom.y > b.left_top.y
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_zone_type_allows_entity() {
        assert!(ZoneType::Mining.allows_entity("electric-mining-drill"));
        assert!(ZoneType::Mining.allows_entity("transport-belt"));
        assert!(!ZoneType::Mining.allows_entity("assembling-machine-1"));

        assert!(ZoneType::Smelting.allows_entity("stone-furnace"));
        assert!(!ZoneType::Smelting.allows_entity("assembling-machine-1"));

        assert!(ZoneType::Assembly.allows_entity("assembling-machine-1"));
        assert!(ZoneType::Assembly.allows_entity("lab"));

        // Reserved allows nothing
        assert!(!ZoneType::Reserved.allows_entity("transport-belt"));

        // Custom allows everything
        assert!(ZoneType::Custom("test".into()).allows_entity("anything"));
    }

    #[test]
    fn test_zone_contains() {
        let zone = Zone::new(
            "test".into(),
            ZoneType::Mining,
            Area::new(0.0, 0.0, 10.0, 10.0),
        );

        assert!(zone.contains(&Position::new(5.0, 5.0)));
        assert!(zone.contains(&Position::new(0.0, 0.0)));
        assert!(!zone.contains(&Position::new(-1.0, 5.0)));
        assert!(!zone.contains(&Position::new(11.0, 5.0)));
    }

    #[test]
    fn test_areas_overlap() {
        let a = Area::new(0.0, 0.0, 10.0, 10.0);
        let b = Area::new(5.0, 5.0, 15.0, 15.0);
        let c = Area::new(20.0, 20.0, 30.0, 30.0);

        assert!(areas_overlap(&a, &b));
        assert!(areas_overlap(&b, &a));
        assert!(!areas_overlap(&a, &c));
    }

    #[test]
    fn test_placement_check() {
        let mut memory = AgentMemory::new();

        // Add a mining zone
        memory.set_zone(Zone::new(
            "mining-1".into(),
            ZoneType::Mining,
            Area::new(0.0, 0.0, 50.0, 50.0),
        ));

        // Add a protected resource
        memory.add_protected_resource(ProtectedResource {
            resource_type: "iron-ore".into(),
            bounds: Area::new(10.0, 10.0, 40.0, 40.0),
            center: Position::new(25.0, 25.0),
            total_amount: 100000,
            tile_count: 900,
        });

        // Miner on ore should be allowed
        let check = memory.check_placement("electric-mining-drill", &Position::new(25.0, 25.0));
        assert!(check.allowed);

        // Assembler on ore should be blocked
        let check = memory.check_placement("assembling-machine-1", &Position::new(25.0, 25.0));
        assert!(!check.allowed);
        assert!(!check.errors.is_empty());
    }
}
