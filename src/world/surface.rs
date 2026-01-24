//! Surface (map) types

use serde::{Deserialize, Serialize};

/// A game surface (map)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Surface {
    /// Surface name (default is "nauvis")
    pub name: String,

    /// Surface index
    pub index: u32,

    /// Time of day (0-1, where 0.5 is noon)
    #[serde(default)]
    pub daytime: Option<f64>,

    /// Darkness level (0-1)
    #[serde(default)]
    pub darkness: Option<f64>,
}

impl Surface {
    /// Check if it's daytime (brightness > 50%)
    pub fn is_day(&self) -> bool {
        self.darkness.map(|d| d < 0.5).unwrap_or(true)
    }
}
