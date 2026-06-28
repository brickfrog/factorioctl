//! Production self-verification command

use anyhow::Result;
use clap::Args;

use super::ResolvedConnectionArgs;
use crate::output::Output;
use crate::world::{build_production_report, Area, Position};

#[derive(Args, Debug)]
pub struct ProductionCommand {
    /// Radius around the character to scan
    #[arg(long)]
    pub radius: Option<u32>,
}

pub async fn execute(cmd: ProductionCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = conn.connect_client().await?;
    let radius = cmd.radius.unwrap_or(32);

    let status = client.character_status().await?;
    let position = match status.position {
        Some(position) => position,
        None => client.get_character_position().await?,
    };
    let scan_area = area_around(position, radius);
    let entities = client.verify_production(scan_area).await?;
    let report = build_production_report(entities);

    Output::new(conn.output).print(&report)?;

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
