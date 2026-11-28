//! Ivy's core: everything that is not screen or OS glue. See docs/CORE.md.

mod account;
mod db;
mod legacy;
mod link;
mod net;
mod profile;
mod provisioning;
mod receive;
mod store;

use std::path::Path;
use std::sync::{Arc, Mutex};

pub use legacy::LegacySummary;
pub use receive::Conversation;

#[allow(clippy::all, dead_code)]
mod proto {
    include!(concat!(env!("OUT_DIR"), "/provisioning_protos.rs"));
    include!(concat!(env!("OUT_DIR"), "/ios_protos.rs"));
    pub mod service {
        include!(concat!(env!("OUT_DIR"), "/signal_service_protos.rs"));
    }
}

uniffi::setup_scaffolding!();

/// Errors the apps show. The message is for logs; the UI picks its own localized text per case.
#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CoreError {
    #[error("database: {0}")]
    Database(String),
    #[error("network: {0}")]
    Network(String),
    #[error("the primary device sent an invalid link message")]
    InvalidProvisioning,
    #[error("the account has too many linked devices")]
    DeviceLimit,
    #[error("this version is too old to link")]
    Obsolete,
    #[error("the server refused the link: {0}")]
    LinkRefused(u16),
    #[error("this device is no longer linked")]
    Unlinked,
}

impl From<rusqlite::Error> for CoreError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Database(e.to_string())
    }
}

/// A QR code as dark/light modules, row by row, without the quiet zone.
#[derive(uniffi::Record)]
pub struct QrCode {
    pub size: u32,
    pub modules: Vec<bool>,
}

fn qr_code(text: &str) -> QrCode {
    let code = qrcode::QrCode::new(text).expect("a link URL fits a QR code");
    QrCode {
        size: code.width() as u32,
        modules: code.to_colors().into_iter().map(|c| c == qrcode::Color::Dark).collect(),
    }
}

/// What the link screen shows while `Core::link` runs.
#[derive(uniffi::Enum)]
pub enum LinkState {
    /// Scan this with the primary device.
    ShowCode { code: QrCode },
    /// The primary device answered; registering with the server.
    Registering,
}

#[uniffi::export(with_foreign)]
pub trait LinkListener: Send + Sync {
    fn link_state(&self, state: LinkState);
}

/// The linked account, as screens show it.
#[derive(uniffi::Record)]
pub struct AccountSummary {
    pub phone_number: Option<String>,
    pub device_id: u32,
}

impl From<&account::Account> for AccountSummary {
    fn from(a: &account::Account) -> Self {
        Self {
            phone_number: a.number.clone(),
            device_id: a.device_id,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait ConversationsListener: Send + Sync {
    /// Something in the conversation list changed; read it again with `Core::conversations`.
    fn conversations_changed(&self);
}

#[derive(uniffi::Object)]
pub struct Core {
    db: Mutex<rusqlite::Connection>,
    net: net::Net,
}

#[uniffi::export(async_runtime = "tokio")]
impl Core {
    /// Opens (or creates) the core database. `key_spec` comes from the Keychain; see `new_key_spec`.
    #[uniffi::constructor]
    pub fn new(database_path: String, key_spec: Vec<u8>, os_version: String) -> Result<Arc<Self>, CoreError> {
        let db = db::open_core(Path::new(&database_path), &key_spec)?;
        Ok(Arc::new(Self {
            db: Mutex::new(db),
            net: net::Net::new(&os_version),
        }))
    }

    pub fn account(&self) -> Result<Option<AccountSummary>, CoreError> {
        Ok(account::load(&self.db.lock().expect("not poisoned"))?
            .as_ref()
            .map(Into::into))
    }

    /// Links this installation as a secondary device. Returns once the account is stored.
    /// shortcut: cannot be cancelled (UniFFI's Swift bindings don't support it); add when a screen needs Cancel.
    pub async fn link(
        &self,
        device_name: String,
        listener: Arc<dyn LinkListener>,
    ) -> Result<AccountSummary, CoreError> {
        let linked = link::link(
            &self.net,
            &device_name,
            &|url| listener.link_state(LinkState::ShowCode { code: qr_code(&url) }),
            &|| listener.link_state(LinkState::Registering),
        )
        .await?;
        let mut db = self.db.lock().expect("not poisoned");
        account::save(&mut db, &linked.account, &linked.aci_keys, linked.pni_keys.as_ref())?;
        Ok((&linked.account).into())
    }

    /// The chats, most recent first.
    pub fn conversations(&self) -> Result<Vec<Conversation>, CoreError> {
        Ok(receive::conversations(&self.db.lock().expect("not poisoned"))?)
    }

    /// Stays connected to Signal and stores incoming messages, reconnecting as needed.
    /// Returns only when this device was unlinked.
    pub async fn receive(&self, listener: Arc<dyn ConversationsListener>) -> Result<(), CoreError> {
        use libsignal_net::chat::server_requests::ServerEvent;
        use libsignal_net::chat::{AuthenticatedChatHeaders, LanguageList};
        use libsignal_net::env::constants::CHAT_WEBSOCKET_PATH;

        let account = account::load(&self.db.lock().expect("not poisoned"))?.ok_or(CoreError::Unlinked)?;
        let aci = libsignal_core::Aci::parse_from_service_id_string(&account.aci).ok_or(CoreError::Unlinked)?;
        let device = libsignal_core::DeviceId::try_from(account.device_id).map_err(|_| CoreError::Unlinked)?;
        let roots = receive::trust_roots();
        let mut backoff = std::time::Duration::from_secs(1);
        loop {
            let headers = AuthenticatedChatHeaders {
                aci,
                device_id: device,
                password: account.password.clone(),
                receive_stories: false.into(),
                languages: LanguageList::default(),
            };
            let (events, mut inbox) = tokio::sync::mpsc::unbounded_channel();
            let connection = self
                .net
                .connect(
                    CHAT_WEBSOCKET_PATH,
                    Some(headers.into()),
                    Box::new(move |event| match ServerEvent::try_from(event) {
                        Ok(event) => drop(events.send(event)),
                        Err(e) => log::warn!("unexpected server request: {e}"),
                    }),
                )
                .await;
            match connection {
                Err(CoreError::Unlinked) => return Err(CoreError::Unlinked),
                Err(e) => log::warn!("receiving: {e}"),
                Ok(connection) => {
                    backoff = std::time::Duration::from_secs(1);
                    let mut tried = std::collections::HashSet::new();
                    if self.fetch_names(&connection, &mut tried).await {
                        listener.conversations_changed();
                    }
                    while let Some(event) = inbox.recv().await {
                        match event {
                            ServerEvent::IncomingMessage {
                                envelope,
                                server_delivery_timestamp,
                                send_ack,
                                ..
                            } => {
                                let changed = {
                                    let db = self.db.lock().expect("not poisoned");
                                    receive::process(&db, &account, &envelope, server_delivery_timestamp, &roots)
                                };
                                // Only after it is stored, so a crash before this means it is delivered again.
                                let _ = send_ack(http::StatusCode::OK);
                                if changed {
                                    self.fetch_names(&connection, &mut tried).await;
                                    listener.conversations_changed();
                                }
                            }
                            ServerEvent::Stopped(_) => break,
                            _ => {}
                        }
                    }
                }
            }
            tokio::time::sleep(backoff).await;
            backoff = (backoff * 2).min(std::time::Duration::from_secs(60));
        }
    }
}

impl Core {
    /// Fetches and decrypts the profile names of contacts whose profile key arrived but whose name
    /// isn't known, each at most once per connection. True when a name was added.
    async fn fetch_names(
        &self,
        chat: &libsignal_net::chat::ChatConnection,
        tried: &mut std::collections::HashSet<String>,
    ) -> bool {
        use base64::Engine as _;
        let missing = profile::missing(&self.db.lock().expect("not poisoned")).unwrap_or_default();
        let mut added = false;
        for (aci, key) in missing {
            if !tried.insert(aci.clone()) {
                continue;
            }
            let Some(path) = profile::path(&aci, &key).and_then(|p| p.parse().ok()) else {
                continue;
            };
            let request = libsignal_net::chat::Request {
                method: http::Method::GET,
                path,
                headers: http::HeaderMap::new(),
                body: None,
            };
            let Ok(response) = chat.send(request, std::time::Duration::from_secs(10)).await else {
                continue;
            };
            let name = (response.status == http::StatusCode::OK)
                .then_some(response.body)
                .flatten()
                .and_then(|body| serde_json::from_slice::<serde_json::Value>(&body).ok())
                .and_then(|profile| profile["name"].as_str().map(str::to_owned))
                .and_then(|encrypted| base64::engine::general_purpose::STANDARD.decode(encrypted).ok())
                .and_then(|encrypted| profile::decrypt_name(&key, &encrypted));
            if let Some(name) = name {
                added |= profile::save(&self.db.lock().expect("not poisoned"), &aci, &name).is_ok();
            }
        }
        added
    }
}

/// A fresh database key for the Keychain: 256-bit key and 128-bit salt.
#[uniffi::export]
pub fn new_key_spec() -> Vec<u8> {
    use rand::{RngCore as _, TryRngCore as _};
    let mut key = vec![0u8; db::KEY_SPEC_LEN];
    rand::rngs::OsRng.unwrap_err().fill_bytes(&mut key);
    key
}

/// Reads what the Swift app's database holds, without writing to it.
#[uniffi::export]
pub fn legacy_summary(database_path: String, key_spec: Vec<u8>) -> Result<LegacySummary, CoreError> {
    legacy::inspect(Path::new(&database_path), &key_spec)
}

#[cfg(test)]
mod tests {
    /// Swift calls the constructor from a plain thread, with no async runtime around it.
    #[test]
    fn core_opens_without_a_runtime_and_starts_unlinked() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("core.sqlite").to_str().unwrap().to_owned();
        let core = super::Core::new(path, super::new_key_spec(), "macOS/15.0".into()).unwrap();
        assert!(core.account().unwrap().is_none());
    }

    #[test]
    fn qr_code_is_square() {
        let code = super::qr_code("sgnl://linkdevice?uuid=abc&pub_key=Bfv7&capabilities=");
        assert_eq!(code.modules.len() as u32, code.size * code.size);
        // Finder pattern: the top-left corner module is dark.
        assert!(code.modules[0]);
    }
}
