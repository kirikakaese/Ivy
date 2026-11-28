//! The linked account and its keys, in the core database.

use libsignal_protocol::GenericSignedPreKey as _;
use rusqlite::{Connection, OptionalExtension as _, params};
use serde::{Deserialize, Serialize};

use crate::CoreError;
use crate::provisioning::LinkKeys;

/// Stored as one JSON value under `kv['account']`. Secrets rely on the database's encryption, as in the Swift app.
#[derive(Serialize, Deserialize, Clone, PartialEq, Debug)]
pub struct Account {
    pub aci: String,
    pub device_id: u32,
    pub password: String,
    pub aci_identity: Vec<u8>,
    pub aci_registration_id: u32,
    pub number: Option<String>,
    pub pni: Option<String>,
    pub pni_identity: Option<Vec<u8>>,
    pub pni_registration_id: Option<u32>,
    pub auth_credential_salt: Option<Vec<u8>>,
    pub profile_key: Vec<u8>,
    pub account_entropy_pool: String,
    pub media_root_backup_key: Vec<u8>,
    pub read_receipts: bool,
}

pub fn load(db: &Connection) -> Result<Option<Account>, CoreError> {
    let json: Option<Vec<u8>> = db
        .query_row("SELECT value FROM kv WHERE key = 'account'", [], |r| r.get(0))
        .optional()?;
    json.map(|j| serde_json::from_slice(&j).map_err(|e| CoreError::Database(e.to_string())))
        .transpose()
}

/// Stores the account with the prekeys the server now holds for it, or nothing.
pub fn save(db: &mut Connection, account: &Account, aci: &LinkKeys, pni: Option<&LinkKeys>) -> Result<(), CoreError> {
    let tx = db.transaction()?;
    tx.execute(
        "INSERT OR REPLACE INTO kv VALUES ('account', ?1)",
        [serde_json::to_vec(account).expect("plain data")],
    )?;
    for (identity, keys) in [(0, Some(aci)), (1, pni)] {
        let Some(keys) = keys else { continue };
        let records = [
            (
                0,
                u32::from(keys.signed.id().expect("built here")),
                keys.signed.serialize(),
            ),
            (
                1,
                u32::from(keys.last_resort.id().expect("built here")),
                keys.last_resort.serialize(),
            ),
        ];
        for (kind, id, record) in records {
            let record = record.map_err(|e| CoreError::Database(e.to_string()))?;
            tx.execute(
                "INSERT INTO prekey VALUES (?1, ?2, ?3, ?4)",
                params![identity, kind, id, record],
            )?;
        }
    }
    Ok(tx.commit()?)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::Account;

    pub(crate) fn account(registration_id: u32) -> Account {
        Account {
            aci: "00000000-0000-4000-8000-000000000001".into(),
            device_id: 2,
            password: "pw".into(),
            aci_identity: vec![],
            aci_registration_id: registration_id,
            number: None,
            pni: None,
            pni_identity: None,
            pni_registration_id: None,
            auth_credential_salt: None,
            profile_key: vec![0; 32],
            account_entropy_pool: String::new(),
            media_root_backup_key: vec![0; 32],
            read_receipts: false,
        }
    }
}
