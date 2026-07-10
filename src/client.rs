use crate::models::NotificationsPage;
use url::Url;

#[derive(Debug, Clone)]
pub struct ApiClient {
    base: Url,
}

#[derive(Debug)]
pub enum ApiError {
    Network(String),
    Http(u16, String),
    Decode(String),
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApiError::Network(msg) => write!(f, "network error: {msg}"),
            ApiError::Http(code, msg) => write!(f, "HTTP {code}: {msg}"),
            ApiError::Decode(msg) => write!(f, "decode error: {msg}"),
        }
    }
}

impl ApiClient {
    pub fn new(base: Url) -> Self {
        Self { base }
    }

    fn build_url(&self, segments: &[&str]) -> Url {
        let mut url = self.base.clone();
        url.path_segments_mut()
            .expect("valid base")
            .extend(segments);
        url
    }

    pub fn notifications(&self, cursor: Option<&str>, count: u32) -> Result<NotificationsPage, ApiError> {
        let mut url = self.build_url(&["api", "sources", "notifications"]);
        if let Some(c) = cursor {
            url.query_pairs_mut().append_pair("cursor", c);
        }
        url.query_pairs_mut().append_pair("count", &count.to_string());
        Self::get_json(url)
    }

    fn get_json<T: serde::de::DeserializeOwned>(url: Url) -> Result<T, ApiError> {
        let resp = reqwest::blocking::Client::new()
            .get(url)
            .timeout(std::time::Duration::from_secs(30))
            .send()
            .map_err(|e| ApiError::Network(e.to_string()))?;
        let status = resp.status();
        let body = resp.text().unwrap_or_default();
        if status.is_success() {
            serde_json::from_str(&body).map_err(|e| ApiError::Decode(e.to_string()))
        } else {
            Err(ApiError::Http(status.as_u16(), body))
        }
    }
}
