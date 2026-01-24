//! Server management commands

use anyhow::Result;
use clap::{Args, Subcommand};
use std::path::PathBuf;

use crate::client::server::ServerManager;

#[derive(Args, Debug)]
pub struct ServerCommand {
    #[command(subcommand)]
    pub command: ServerSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum ServerSubcommand {
    /// Create a new map/save file
    Create {
        /// Name for the save file
        #[arg(long)]
        name: String,

        /// Enable peaceful mode (no enemy attacks)
        #[arg(long)]
        peaceful: bool,

        /// Map generation seed
        #[arg(long)]
        seed: Option<u32>,

        /// Path to map generation settings JSON
        #[arg(long)]
        map_gen_settings: Option<PathBuf>,

        /// Path to map settings JSON
        #[arg(long)]
        map_settings: Option<PathBuf>,
    },

    /// Start a headless server
    Start {
        /// Path to save file
        #[arg(long)]
        save: PathBuf,

        /// RCON port
        #[arg(long, default_value = "27015")]
        rcon_port: u16,

        /// RCON password
        #[arg(long, default_value = "")]
        rcon_password: String,

        /// Path to server settings JSON
        #[arg(long)]
        server_settings: Option<PathBuf>,
    },

    /// Stop the running server
    Stop,

    /// Check server status
    Status,
}

pub async fn execute(cmd: ServerCommand) -> Result<()> {
    let mut manager = ServerManager::new()?;

    match cmd.command {
        ServerSubcommand::Create {
            name,
            peaceful,
            seed,
            map_gen_settings,
            map_settings,
        } => {
            let save_path = manager
                .create_map(&name, peaceful, seed, map_gen_settings, map_settings)
                .await?;
            println!("Created save: {}", save_path.display());
        }
        ServerSubcommand::Start {
            save,
            rcon_port,
            rcon_password,
            server_settings,
        } => {
            manager
                .start_server(&save, rcon_port, &rcon_password, server_settings)
                .await?;
            println!("Server started on RCON port {}", rcon_port);
        }
        ServerSubcommand::Stop => {
            manager.stop_server().await?;
            println!("Server stopped");
        }
        ServerSubcommand::Status => {
            let status = manager.status().await?;
            println!("{}", status);
        }
    }

    Ok(())
}
