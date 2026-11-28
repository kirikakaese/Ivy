//! Ivy's core: everything that is not screen or OS glue. See docs/CORE.md.

mod account;
mod db;
mod legacy;
mod link;
mod net;
mod provisioning;

use std::path::Path;
use std::sync::{Arc, Mutex};

pub use legacy::LegacySummary;

#[allow(clippy::all)]
mod proto {
    include!(concat!(env!("OUT_DIR"), "/provisioning_protos.rs"));
    include!(concat!(env!("OUT_DIR"), "/ios_protos.rs"));
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
