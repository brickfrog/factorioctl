//! Result types for high-level operations

use serde::{Deserialize, Serialize};

use super::entity::InventoryItem;
use super::Position;
use super::Entity;

/// Result of a gather operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatherResult {
    pub success: bool,
    pub resource_name: String,
    pub gathered: u32,
    pub distance_walked: f64,
    pub inventory: Vec<InventoryItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Result of a walk-to operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalkResult {
    pub arrived: bool,
    pub final_position: Position,
    pub distance_walked: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// Result of a build operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildResult {
    pub placed: u32,
    pub total: u32,
    pub entities: Vec<Entity>,
    pub errors: Vec<String>,
}

/// Entity placement specification for bulk placement
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlacementSpec {
    pub name: String,
    pub position: (f64, f64),
    #[serde(default)]
    pub direction: Option<String>,
}

/// Summary of items on a single belt
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeltItemSummary {
    pub position: Position,
    pub unit_number: u32,
    pub items: Vec<InventoryItem>,
}

/// Result of querying belt contents
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeltContentsResult {
    pub belt_count: u32,
    pub total_items: u32,
    pub item_summary: Vec<InventoryItem>,
    pub belts: Vec<BeltItemSummary>,
}
