//! Server process management

use anyhow::{bail, Context, Result};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::{Child, Command};

/// Manages Factorio server processes
pub struct ServerManager {
    factorio_binary: PathBuf,
    saves_dir: PathBuf,
    server_process: Option<Child>,
}

impl ServerManager {
    /// Create a new server manager
    pub fn new() -> Result<Self> {
        let factorio_binary = find_factorio_binary()?;
        let saves_dir = std::env::current_dir()?.join("saves");

        // Ensure saves directory exists
        std::fs::create_dir_all(&saves_dir)?;

        Ok(Self {
            factorio_binary,
            saves_dir,
            server_process: None,
        })
    }

    /// Create a new map/save file
    pub async fn create_map(
        &self,
        name: &str,
        peaceful: bool,
        seed: Option<u32>,
        map_gen_settings: Option<PathBuf>,
        map_settings: Option<PathBuf>,
    ) -> Result<PathBuf> {
        let save_path = self.saves_dir.join(format!("{}.zip", name));

        let mut cmd = Command::new(&self.factorio_binary);
        cmd.arg("--create").arg(&save_path);

        if peaceful {
            // Use a map gen settings file with peaceful mode if available
            // Otherwise we'd need to create one
        }

        if let Some(seed) = seed {
            cmd.arg("--map-gen-seed").arg(seed.to_string());
        }

        if let Some(path) = map_gen_settings {
            cmd.arg("--map-gen-settings").arg(path);
        }

        if let Some(path) = map_settings {
            cmd.arg("--map-settings").arg(path);
        }

        let output = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?
            .wait_with_output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            bail!("Failed to create map: {}", stderr);
        }

        if !save_path.exists() {
            bail!("Save file was not created");
        }

        Ok(save_path)
    }

    /// Start a headless server
    pub async fn start_server(
        &mut self,
        save_path: &PathBuf,
        rcon_port: u16,
        rcon_password: &str,
        server_settings: Option<PathBuf>,
    ) -> Result<()> {
        if self.server_process.is_some() {
            bail!("Server already running");
        }

        let mut cmd = Command::new(&self.factorio_binary);
        cmd.arg("--start-server")
            .arg(save_path)
            .arg("--rcon-port")
            .arg(rcon_port.to_string())
            .arg("--rcon-password")
            .arg(rcon_password);

        if let Some(path) = server_settings {
            cmd.arg("--server-settings").arg(path);
        }

        let child = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to start server")?;

        self.server_process = Some(child);

        // Wait a bit for server to start
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        Ok(())
    }

    /// Stop the running server
    pub async fn stop_server(&mut self) -> Result<()> {
        if let Some(mut child) = self.server_process.take() {
            child.kill().await?;
            child.wait().await?;
        }
        Ok(())
    }

    /// Get server status
    pub async fn status(&self) -> Result<String> {
        if let Some(ref child) = self.server_process {
            if let Some(id) = child.id() {
                return Ok(format!("Running (PID: {})", id));
            }
        }
        Ok("Not running".to_string())
    }
}

/// Find the Factorio binary on the system
fn find_factorio_binary() -> Result<PathBuf> {
    // Check common installation paths
    let candidates = vec![
        // macOS Steam
        PathBuf::from("/Users")
            .join(whoami::username())
            .join("Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio"),
        // macOS standalone
        PathBuf::from("/Applications/factorio.app/Contents/MacOS/factorio"),
        // Linux Steam
        PathBuf::from(std::env::var("HOME").unwrap_or_default())
            .join(".steam/steam/steamapps/common/Factorio/bin/x64/factorio"),
        // Linux standalone
        PathBuf::from("/opt/factorio/bin/x64/factorio"),
        // Windows Steam (via WSL or native)
        PathBuf::from("C:/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe"),
        PathBuf::from("C:/Program Files/Factorio/bin/x64/factorio.exe"),
    ];

    for path in candidates {
        if path.exists() {
            return Ok(path);
        }
    }

    // Check if factorio is in PATH
    if let Ok(path) = which::which("factorio") {
        return Ok(path);
    }

    bail!(
        "Could not find Factorio binary. Please ensure Factorio is installed or set FACTORIO_PATH environment variable."
    )
}

impl Drop for ServerManager {
    fn drop(&mut self) {
        // Try to clean up server process
        if let Some(mut child) = self.server_process.take() {
            let _ = child.start_kill();
        }
    }
}
