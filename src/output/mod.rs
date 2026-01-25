//! Output formatting for CLI results

mod human;
mod json;

use anyhow::Result;
use serde::Serialize;

/// Output format for commands
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, clap::ValueEnum)]
pub enum OutputFormat {
    /// Human-readable output
    #[default]
    Human,
    /// JSON output for machine consumption
    Json,
}

/// Trait for types that can be output
pub trait Outputable: Serialize {
    /// Format for human-readable output
    fn format_human(&self) -> String;
}

/// Output formatter
pub struct Output {
    format: OutputFormat,
}

impl Output {
    pub fn new(format: OutputFormat) -> Self {
        Self { format }
    }

    /// Print a value according to the output format
    pub fn print<T: Outputable>(&self, value: &T) -> Result<()> {
        match self.format {
            OutputFormat::Human => {
                println!("{}", value.format_human());
            }
            OutputFormat::Json => {
                println!("{}", serde_json::to_string_pretty(value)?);
            }
        }
        Ok(())
    }
}

// Implement Outputable for common types

impl Outputable for crate::world::Tick {
    fn format_human(&self) -> String {
        format!("Tick: {} ({:.1}s)", self.tick, self.to_seconds())
    }
}

impl Outputable for Vec<crate::world::Surface> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No surfaces".to_string();
        }
        self.iter()
            .map(|s| {
                format!(
                    "{} (index: {}, daytime: {:.2})",
                    s.name,
                    s.index,
                    s.daytime.unwrap_or(0.5)
                )
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
}

impl Outputable for Vec<crate::world::Entity> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No entities found".to_string();
        }
        let mut lines = vec![format!("Found {} entities:", self.len())];
        for e in self {
            lines.push(format!(
                "  #{} {} at ({:.1}, {:.1})",
                e.unit_number.unwrap_or(0),
                e.name,
                e.position.x,
                e.position.y
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::Entity {
    fn format_human(&self) -> String {
        format!(
            "Entity #{}: {} at ({:.1}, {:.1})\n  Type: {}\n  Direction: {}\n  Health: {}\n  Force: {}",
            self.unit_number.unwrap_or(0),
            self.name,
            self.position.x,
            self.position.y,
            self.entity_type.as_deref().unwrap_or("unknown"),
            self.direction,
            self.health.map(|h| format!("{:.0}", h)).unwrap_or_else(|| "N/A".to_string()),
            self.force.as_deref().unwrap_or("none")
        )
    }
}

impl Outputable for Vec<crate::world::ResourcePatch> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No resources found".to_string();
        }
        let mut lines = vec![format!("Found {} resource patches:", self.len())];
        for r in self {
            lines.push(format!(
                "  {} at ({:.1}, {:.1}): {} total ({} tiles)",
                r.name, r.center.x, r.center.y, r.total_amount, r.tile_count
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::ResourcePatch {
    fn format_human(&self) -> String {
        format!(
            "Resource Patch: {}\n  Center: ({:.1}, {:.1})\n  Total: {}\n  Tiles: {}\n  Bounds: ({:.0},{:.0}) to ({:.0},{:.0})",
            self.name,
            self.center.x,
            self.center.y,
            self.total_amount,
            self.tile_count,
            self.bounding_box.left_top.x,
            self.bounding_box.left_top.y,
            self.bounding_box.right_bottom.x,
            self.bounding_box.right_bottom.y
        )
    }
}

impl Outputable for Vec<crate::world::Tile> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No tiles".to_string();
        }
        format!("Found {} tiles", self.len())
    }
}

impl Outputable for crate::world::Tile {
    fn format_human(&self) -> String {
        format!(
            "Tile: {} at ({}, {})\n  Walkable: {}",
            self.name,
            self.position.x as i32,
            self.position.y as i32,
            !self.collides_with_player
        )
    }
}

impl Outputable for crate::world::CharacterStatus {
    fn format_human(&self) -> String {
        if !self.valid {
            return "Character not initialized".to_string();
        }
        format!(
            "Character #{}\n  Position: ({:.1}, {:.1})\n  Health: {:.0}\n  Crafting queue: {}\n  Walking: {}",
            self.unit_number.unwrap_or(0),
            self.position.as_ref().map(|p| p.x).unwrap_or(0.0),
            self.position.as_ref().map(|p| p.y).unwrap_or(0.0),
            self.health.unwrap_or(0.0),
            self.crafting_queue_size.unwrap_or(0),
            self.walking.unwrap_or(false)
        )
    }
}

impl Outputable for crate::world::Inventory {
    fn format_human(&self) -> String {
        if self.items.is_empty() {
            return format!("Inventory: empty ({} free slots)", self.free_slots);
        }
        let mut lines = vec![format!(
            "Inventory ({} items, {} free slots):",
            self.items.len(),
            self.free_slots
        )];
        for item in &self.items {
            lines.push(format!("  {} x{}", item.name, item.count));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::MineResult {
    fn format_human(&self) -> String {
        if !self.success {
            return format!(
                "Mining failed: {}",
                self.error.as_deref().unwrap_or("unknown error")
            );
        }
        format!("Mined {} entities", self.mined_count)
    }
}

impl Outputable for crate::world::CraftResult {
    fn format_human(&self) -> String {
        if !self.success {
            return format!(
                "Crafting failed: {}",
                self.error.as_deref().unwrap_or("unknown error")
            );
        }
        let mut output = format!(
            "Queued {} items for crafting (queue size: {})",
            self.queued, self.queue_size
        );
        if !self.queue.is_empty() {
            output.push_str("\nCrafting queue:");
            for item in &self.queue {
                output.push_str(&format!("\n  {} x{}", item.recipe, item.count));
            }
        }
        output
    }
}

impl Outputable for crate::world::GatherResult {
    fn format_human(&self) -> String {
        if !self.success {
            return format!(
                "Gathering failed: {}",
                self.error.as_deref().unwrap_or("unknown error")
            );
        }
        let mut lines = vec![format!(
            "Gathered {} {} (walked {:.1} tiles)",
            self.gathered, self.resource_name, self.distance_walked
        )];
        if !self.inventory.is_empty() {
            lines.push("Inventory:".to_string());
            for item in &self.inventory {
                lines.push(format!("  {} x{}", item.name, item.count));
            }
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::WalkResult {
    fn format_human(&self) -> String {
        if self.arrived {
            format!(
                "Arrived at ({:.1}, {:.1}) after walking {:.1} tiles",
                self.final_position.x, self.final_position.y, self.distance_walked
            )
        } else {
            format!(
                "Stopped at ({:.1}, {:.1}) after walking {:.1} tiles: {}",
                self.final_position.x,
                self.final_position.y,
                self.distance_walked,
                self.reason.as_deref().unwrap_or("unknown reason")
            )
        }
    }
}

impl Outputable for crate::world::BuildResult {
    fn format_human(&self) -> String {
        let mut lines = vec![format!("Placed {}/{} entities", self.placed, self.total)];
        for entity in &self.entities {
            lines.push(format!(
                "  #{} {} at ({:.1}, {:.1})",
                entity.unit_number.unwrap_or(0),
                entity.name,
                entity.position.x,
                entity.position.y
            ));
        }
        if !self.errors.is_empty() {
            lines.push("Errors:".to_string());
            for err in &self.errors {
                lines.push(format!("  - {}", err));
            }
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::Recipe {
    fn format_human(&self) -> String {
        let mut lines = vec![
            format!("Recipe: {}", self.name),
            format!("  Category: {}", self.category),
            format!("  Crafting time: {:.1}s", self.energy),
        ];
        if !self.ingredients.is_empty() {
            lines.push("  Ingredients:".to_string());
            for ing in &self.ingredients {
                lines.push(format!("    - {} x{}", ing.name, ing.amount));
            }
        }
        if !self.products.is_empty() {
            lines.push("  Products:".to_string());
            for prod in &self.products {
                let prob = prod
                    .probability
                    .map(|p| format!(" ({:.0}%)", p * 100.0))
                    .unwrap_or_default();
                lines.push(format!("    - {} x{}{}", prod.name, prod.amount, prob));
            }
        }
        lines.join("\n")
    }
}

impl Outputable for Vec<crate::world::Recipe> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No recipes found".to_string();
        }
        let mut lines = vec![format!("Found {} recipes:", self.len())];
        for recipe in self {
            lines.push(format!(
                "  {} ({}, {:.1}s)",
                recipe.name, recipe.category, recipe.energy
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for Vec<crate::world::RecipeSummary> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No recipes found".to_string();
        }
        let mut lines = vec![format!("Found {} recipes:", self.len())];
        for recipe in self {
            lines.push(format!(
                "  {} ({}, {:.1}s)",
                recipe.name, recipe.category, recipe.energy
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::Prototype {
    fn format_human(&self) -> String {
        let mut lines = vec![
            format!("Entity: {}", self.name),
            format!("  Type: {}", self.entity_type),
        ];
        if let Some(size) = &self.size {
            lines.push(format!("  Size: {:.0}x{:.0}", size[0], size[1]));
        }
        if let Some(speed) = self.crafting_speed {
            lines.push(format!("  Crafting speed: {:.1}", speed));
        }
        if let Some(cats) = &self.crafting_categories {
            lines.push(format!("  Crafting categories: [{}]", cats.join(", ")));
        }
        if let Some(speed) = self.mining_speed {
            lines.push(format!("  Mining speed: {:.2}", speed));
        }
        if let Some(cats) = &self.resource_categories {
            lines.push(format!("  Resource categories: [{}]", cats.join(", ")));
        }
        if let Some(speed) = self.belt_speed {
            lines.push(format!("  Belt speed: {:.2} items/tick", speed));
        }
        if let Some(source) = &self.energy_source {
            lines.push(format!("  Energy source: {}", source));
        }
        if let Some(usage) = self.energy_usage {
            lines.push(format!("  Energy usage: {:.0}W", usage));
        }
        lines.join("\n")
    }
}

// --- Native Blueprint Types ---

impl Outputable for crate::world::NativeBlueprintExport {
    fn format_human(&self) -> String {
        format!(
            "Blueprint ({} entities):\n{}",
            self.entity_count, self.blueprint_string
        )
    }
}

impl Outputable for crate::world::BlueprintSaveResult {
    fn format_human(&self) -> String {
        if self.success {
            format!("Saved blueprint ({} entities)", self.entity_count)
        } else {
            format!(
                "Failed to save: {}",
                self.error.as_deref().unwrap_or("unknown error")
            )
        }
    }
}

impl Outputable for Vec<crate::world::StoredBlueprint> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No saved blueprints".to_string();
        }
        let mut lines = vec![format!("Saved blueprints ({}):", self.len())];
        for bp in self {
            lines.push(format!("  {} ({} entities)", bp.name, bp.entity_count));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::world::BlueprintPlaceResult {
    fn format_human(&self) -> String {
        if self.success {
            if self.ghosts_created > 0 {
                format!("Placed blueprint ({} ghost entities)", self.ghosts_created)
            } else {
                "Placed blueprint".to_string()
            }
        } else {
            format!(
                "Failed to place: {}",
                self.error.as_deref().unwrap_or("unknown error")
            )
        }
    }
}

// --- Analyze Types ---

impl Outputable for crate::analyze::BeltReachResult {
    fn format_human(&self) -> String {
        let mut lines = vec![
            format!("Belt Reachability from ({}, {})", self.origin.x, self.origin.y),
            format!("  Total connected belts: {}", self.total_belts),
            format!("  Upstream belts: {}", self.upstream.len()),
            format!("  Downstream belts: {}", self.downstream.len()),
        ];
        if !self.upstream_endpoints.is_empty() {
            lines.push(format!("  Input endpoints ({}):", self.upstream_endpoints.len()));
            for ep in &self.upstream_endpoints {
                lines.push(format!("    ({}, {})", ep.x, ep.y));
            }
        }
        if !self.downstream_endpoints.is_empty() {
            lines.push(format!("  Output endpoints ({}):", self.downstream_endpoints.len()));
            for ep in &self.downstream_endpoints {
                lines.push(format!("    ({}, {})", ep.x, ep.y));
            }
        }
        lines.join("\n")
    }
}

impl Outputable for crate::analyze::BeltNetworkResult {
    fn format_human(&self) -> String {
        let mut lines = vec![
            format!("Belt Networks: {} total", self.total_networks),
            format!("Total belts: {}", self.total_belts),
        ];
        for network in &self.networks {
            lines.push(format!(
                "  Network #{}: {} belts, {} inputs, {} outputs",
                network.id, network.belt_count, network.inputs.len(), network.outputs.len()
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::analyze::BeltGapResult {
    fn format_human(&self) -> String {
        if self.gaps.is_empty() {
            return "No gaps found in belt network".to_string();
        }
        let mut lines = vec![format!("Found {} gaps:", self.gap_count)];
        for gap in &self.gaps {
            let gap_desc = match &gap.gap_type {
                crate::analyze::GapType::Missing => "missing belt".to_string(),
                crate::analyze::GapType::Misaligned => {
                    format!("misaligned: {}", gap.blocker.as_deref().unwrap_or(""))
                }
                crate::analyze::GapType::Blocked => {
                    format!("blocked by: {}", gap.blocker.as_deref().unwrap_or("unknown"))
                }
            };
            lines.push(format!(
                "  ({}, {}) -> ({}, {}) [{:?}]: {}",
                gap.from.x, gap.from.y, gap.to.x, gap.to.y, gap.from_direction, gap_desc
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for Vec<crate::analyze::InserterAnalysis> {
    fn format_human(&self) -> String {
        if self.is_empty() {
            return "No inserters found".to_string();
        }
        let mut lines = vec![format!("Found {} inserters:", self.len())];
        for inserter in self {
            lines.push(format!(
                "  #{} {} at ({}, {}) facing {:?}",
                inserter.unit_number,
                inserter.inserter_type,
                inserter.position.x,
                inserter.position.y,
                inserter.direction
            ));
            let pickup = inserter
                .pickup_target
                .as_ref()
                .map(|e| e.name.as_str())
                .unwrap_or("empty");
            let dropoff = inserter
                .dropoff_target
                .as_ref()
                .map(|e| e.name.as_str())
                .unwrap_or("empty");
            lines.push(format!(
                "    Pickup ({}, {}): {}",
                inserter.pickup_position.x, inserter.pickup_position.y, pickup
            ));
            lines.push(format!(
                "    Dropoff ({}, {}): {}",
                inserter.dropoff_position.x, inserter.dropoff_position.y, dropoff
            ));
        }
        lines.join("\n")
    }
}

impl Outputable for crate::analyze::EntityReachResult {
    fn format_human(&self) -> String {
        let mut lines = vec![
            format!(
                "Entity reach analysis at ({}, {}) radius {}:",
                self.origin.x, self.origin.y, self.radius
            ),
            format!("  Belts in range: {}", self.belts.len()),
            format!("  Inserters interacting: {}", self.inserters.len()),
            format!("  Other entities: {}", self.interacting_entities.len()),
        ];
        if !self.inserters.is_empty() {
            lines.push("  Interacting inserters:".to_string());
            for inserter in &self.inserters {
                let role = if inserter.pickup_position == self.origin {
                    "picks up from"
                } else {
                    "drops to"
                };
                lines.push(format!(
                    "    #{} {} {} this position",
                    inserter.unit_number, inserter.inserter_type, role
                ));
            }
        }
        lines.join("\n")
    }
}
