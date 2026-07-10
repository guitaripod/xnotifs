use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_font_scale")]
    pub font_scale: f64,

    #[serde(default = "default_show_thumbnails")]
    pub show_thumbnails: bool,

    #[serde(default = "default_window_width")]
    pub window_width: i32,

    #[serde(default = "default_window_height")]
    pub window_height: i32,

    #[serde(default = "default_poll_interval_secs")]
    pub poll_interval_secs: u64,

    #[serde(default = "default_server_url")]
    pub server_url: String,
}

fn default_font_scale() -> f64 {
    1.0
}
fn default_show_thumbnails() -> bool {
    true
}
fn default_window_width() -> i32 {
    520
}
fn default_window_height() -> i32 {
    960
}
fn default_poll_interval_secs() -> u64 {
    15
}
fn default_server_url() -> String {
    "http://localhost:7777".into()
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            font_scale: default_font_scale(),
            show_thumbnails: default_show_thumbnails(),
            window_width: default_window_width(),
            window_height: default_window_height(),
            poll_interval_secs: default_poll_interval_secs(),
            server_url: default_server_url(),
        }
    }
}

impl Settings {
    fn path() -> PathBuf {
        let base = dirs_next().unwrap_or_else(|| PathBuf::from("."));
        base.join("settings.toml")
    }

    pub fn load() -> Self {
        let path = Self::path();
        if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|s| toml::from_str(&s).ok())
                .unwrap_or_default()
        } else {
            Self::default()
        }
    }

    pub fn save(&self) {
        let path = Self::path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(s) = toml::to_string_pretty(self) {
            let _ = std::fs::write(&path, s);
        }
    }
}

fn dirs_next() -> Option<PathBuf> {
    if let Some(d) = dirs::config_dir() {
        Some(d.join("xnotifs"))
    } else {
        None
    }
}
