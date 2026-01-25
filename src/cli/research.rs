//! Research/technology commands

use anyhow::Result;
use clap::{Args, Subcommand};

use super::ResolvedConnectionArgs;
use crate::client::FactorioClient;

#[derive(Args, Debug)]
pub struct ResearchCommand {
    #[command(subcommand)]
    pub command: ResearchSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum ResearchSubcommand {
    /// Show research status (completed and available)
    Status,

    /// List available technologies to research
    Available,

    /// Show current research progress
    Current,

    /// Start researching a technology
    Start {
        /// Technology name
        tech: String,
    },
}

pub async fn execute(cmd: ResearchCommand, conn: &ResolvedConnectionArgs) -> Result<()> {
    let mut client = FactorioClient::connect(&conn.host, conn.port, &conn.password).await?;

    match cmd.command {
        ResearchSubcommand::Status => {
            let response = client
                .execute_lua(
                    r#"
local force = game.forces.player
local researched = {}
local available = {}
for name, tech in pairs(force.technologies) do
    if tech.researched then
        table.insert(researched, name)
    elseif tech.enabled then
        local all_met = true
        for _, prereq in pairs(tech.prerequisites) do
            if not prereq.researched then
                all_met = false
                break
            end
        end
        if all_met then
            table.insert(available, name)
        end
    end
end
table.sort(researched)
table.sort(available)
rcon.print(helpers.table_to_json({researched = researched, available = available}))
"#,
                )
                .await?;

            #[derive(serde::Deserialize)]
            struct Status {
                researched: Vec<String>,
                available: Vec<String>,
            }
            let status: Status = serde_json::from_str(&response)?;

            println!("Researched technologies ({}):", status.researched.len());
            for tech in &status.researched {
                println!("  {}", tech);
            }
            println!("\nAvailable to research ({}):", status.available.len());
            for tech in &status.available {
                println!("  {}", tech);
            }
        }

        ResearchSubcommand::Available => {
            let response = client
                .execute_lua(
                    r#"
local force = game.forces.player
local available = {}
for name, tech in pairs(force.technologies) do
    if not tech.researched and tech.enabled then
        local all_met = true
        for _, prereq in pairs(tech.prerequisites) do
            if not prereq.researched then
                all_met = false
                break
            end
        end
        if all_met then
            local packs = {}
            for _, ing in pairs(tech.research_unit_ingredients) do
                table.insert(packs, ing.name .. " x" .. ing.amount)
            end
            table.insert(available, {
                name = name,
                cost = tech.research_unit_count,
                packs = table.concat(packs, ", ")
            })
        end
    end
end
rcon.print(helpers.table_to_json(available))
"#,
                )
                .await?;

            #[derive(serde::Deserialize)]
            struct Tech {
                name: String,
                cost: u32,
                packs: String,
            }
            let techs: Vec<Tech> = serde_json::from_str(&response)?;

            if techs.is_empty() {
                println!("No technologies available to research");
            } else {
                println!("Available technologies:");
                for tech in &techs {
                    if tech.packs.is_empty() {
                        println!("  {} ({} units)", tech.name, tech.cost);
                    } else {
                        println!("  {} ({} units: {})", tech.name, tech.cost, tech.packs);
                    }
                }
            }
        }

        ResearchSubcommand::Current => {
            let response = client
                .execute_lua(
                    r#"
local force = game.forces.player
local current = force.current_research
if current then
    local progress = force.research_progress
    rcon.print(helpers.table_to_json({
        name = current.name,
        progress = progress,
        cost = current.research_unit_count
    }))
else
    rcon.print('{"name": null}')
end
"#,
                )
                .await?;

            #[derive(serde::Deserialize)]
            struct Current {
                name: Option<String>,
                progress: Option<f64>,
                cost: Option<u32>,
            }
            let current: Current = serde_json::from_str(&response)?;

            if let Some(name) = current.name {
                let progress = current.progress.unwrap_or(0.0);
                let cost = current.cost.unwrap_or(1);
                println!(
                    "Researching: {} ({:.1}% complete, {}/{})",
                    name,
                    progress * 100.0,
                    (progress * cost as f64) as u32,
                    cost
                );
            } else {
                println!("No research in progress");
            }
        }

        ResearchSubcommand::Start { tech } => {
            // In Factorio 2.0, we directly complete research (for headless/dev use)
            // Normal gameplay would use labs with science packs
            let response = client
                .execute_lua(&format!(
                    r#"
local force = game.forces.player
local tech = force.technologies["{}"]
if not tech then
    rcon.print('{{"success": false, "error": "Technology not found"}}')
elseif tech.researched then
    rcon.print('{{"success": false, "error": "Already researched"}}')
else
    tech.researched = true
    rcon.print('{{"success": true}}')
end
"#,
                    tech
                ))
                .await?;

            #[derive(serde::Deserialize)]
            struct Result {
                success: bool,
                error: Option<String>,
            }
            let result: Result = serde_json::from_str(&response)?;

            if result.success {
                println!("Researched: {}", tech);
            } else {
                println!(
                    "Failed: {}",
                    result.error.unwrap_or_else(|| "unknown error".to_string())
                );
            }
        }
    }

    client.close().await?;
    Ok(())
}
