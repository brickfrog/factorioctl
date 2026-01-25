//! Recipe types for Factorio prototypes

use serde::{Deserialize, Serialize};

/// A crafting recipe
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Recipe {
    /// Recipe name (e.g., "iron-plate")
    pub name: String,
    /// Crafting category (e.g., "smelting", "crafting")
    pub category: String,
    /// Crafting time in seconds (energy / crafting_speed)
    pub energy: f64,
    /// Required ingredients
    pub ingredients: Vec<Ingredient>,
    /// Produced items
    pub products: Vec<Product>,
}

/// An ingredient in a recipe
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ingredient {
    /// Type: "item" or "fluid"
    #[serde(rename = "type")]
    pub item_type: String,
    /// Item/fluid name
    pub name: String,
    /// Amount required
    pub amount: f64,
}

/// A product of a recipe
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Product {
    /// Type: "item" or "fluid"
    #[serde(rename = "type")]
    pub item_type: String,
    /// Item/fluid name
    pub name: String,
    /// Amount produced
    pub amount: f64,
    /// Probability of production (for recipes with random outputs)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub probability: Option<f64>,
}

impl Recipe {
    /// Calculate items produced per minute at a given crafting speed
    pub fn items_per_minute(&self, crafting_speed: f64) -> f64 {
        if self.energy <= 0.0 {
            return 0.0;
        }
        let crafts_per_minute = 60.0 / (self.energy / crafting_speed);
        // Use the first product's amount as the output
        let output_amount = self.products.first().map(|p| p.amount).unwrap_or(1.0);
        crafts_per_minute * output_amount
    }

    /// Calculate how many machines needed to produce target items per minute
    pub fn machines_needed(&self, target_per_minute: f64, crafting_speed: f64) -> f64 {
        let per_machine = self.items_per_minute(crafting_speed);
        if per_machine <= 0.0 {
            return 0.0;
        }
        target_per_minute / per_machine
    }
}

/// Summary of a recipe (for listing)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecipeSummary {
    pub name: String,
    pub category: String,
    pub energy: f64,
}
