use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Media {
    pub url: String,
    pub kind: MediaKind,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub alt_text: Option<String>,
    pub duration_secs: Option<f64>,
    pub poster_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Photo,
    Video,
    AnimatedGif,
    LinkCard,
    YouTube,
    Poll,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationActor {
    pub handle: String,
    pub name: String,
    pub rest_id: String,
    pub verified: bool,
    pub avatar_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    #[serde(alias = "type")]
    pub kind: String,
    pub id: String,
    pub actors: Vec<NotificationActor>,
    pub target_tweet_id: Option<String>,
    pub target_tweet_snippet: Option<String>,
    pub target_tweet_like_count: Option<u64>,
    pub target_media: Vec<Media>,
    pub others_count: Option<u32>,
    pub message: Option<String>,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationsPage {
    pub notifications: Vec<Notification>,
    pub cursor: Option<String>,
}


