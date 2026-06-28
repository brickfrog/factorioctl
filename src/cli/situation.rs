//! Compact situational report command

use anyhow::Result;
use clap::Args;

use super::{OutputFormat, ResolvedConnectionArgs};
use crate::world::{Area, Position, build_situation_report};

#[derive(Args, Debug)]
pub struct SituationCommand {
    /// Radius around the character to scan
    #[arg(long)]
    pub radius: Option<u32>,
}

pub async fn execute(cmd: SituationCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = conn.connect_client().await?;
    let radius = cmd.radius.unwrap_or(32);

    let status = client.character_status().await?;
    let position = match status.position {
        Some(position) => position,
        None => client.get_character_position().await?,
    };
    let scan_area = area_around(position, radius);
    let inventory = client.character_inventory().await?;
    let entities = client.find_entities(scan_area, None, None).await?;
    let resources = client.find_resources(scan_area, None).await?;
    let tick = client.get_tick().await?;

    let report = build_situation_report(
        position,
        status.health,
        status.walking,
        tick.tick,
        inventory.items,
        entities,
        resources,
        radius,
    );

    let rendered = match conn.output {
        OutputFormat::Human | OutputFormat::Json => serde_json::to_string_pretty(&report)?,
    };
    println!("{}", rendered);

    client.close().await?;
    Ok(())
}

fn area_around(position: Position, radius: u32) -> Area {
    let radius = radius as f64;
    Area {
        left_top: Position::new(position.x - radius, position.y - radius),
        right_bottom: Position::new(position.x + radius, position.y + radius),
    }
}
