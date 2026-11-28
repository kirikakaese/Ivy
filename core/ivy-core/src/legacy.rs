//! Read-only look at the Swift app's database (`grdb/signal.sqlite`). Nothing here writes.

use std::path::Path;

use libsignal_protocol::{PrivateKey, PublicKey};
use plist::Value;
use rusqlite::{Connection, OptionalExtension as _, types::ValueRef};

use crate::{CoreError, db};

/// What the existing installation holds. No secrets.
#[derive(uniffi::Record, Debug, PartialEq)]
pub struct LegacySummary {
    /// Linked or registered, with an identity key that is a valid key pair.
    pub has_account: bool,
    pub phone_number: Option<String>,
    pub device_id: Option<u32>,
    pub chats: u64,
    pub messages: u64,
}

/// Root object of an `NSKeyedArchiver` archive, the form the old `KeyValueStore` writes.
fn unarchive(blob: &[u8]) -> Option<(Vec<Value>, Value)> {
    let mut archive = plist::from_bytes::<Value>(blob).ok()?.into_dictionary()?;
    let objects = archive.remove("$objects")?.into_array()?;
    let root = archive.get("$top")?.as_dictionary()?.get("root")?.as_uid()?.get() as usize;
    let root = objects.get(root)?.clone();
    Some((objects, root))
}

fn value(db: &Connection, collection: &str, key: &str) -> Result<Option<(Vec<Value>, Value)>, CoreError> {
    let found = db
        .query_row(
            "SELECT value FROM keyvalue WHERE collection = ?1 AND key = ?2",
            [collection, key],
            |r| {
                Ok(match r.get_ref(0)? {
                    // Values moved to `NewKeyValueStore` are plain SQLite values.
                    ValueRef::Blob(b) if b.starts_with(b"bplist00") => unarchive(b),
                    ValueRef::Blob(b) => Some((vec![], Value::Data(b.to_vec()))),
                    ValueRef::Text(t) => Some((vec![], Value::String(String::from_utf8_lossy(t).into_owned()))),
                    ValueRef::Integer(i) => Some((vec![], Value::Integer(i.into()))),
                    _ => None,
                })
            },
        )
        .optional()?;
    Ok(found.flatten())
}

/// `ECKeyPair`: raw 32-byte public and private keys.
fn is_key_pair(objects: &[Value], root: &Value) -> bool {
    let field = |name: &str| {
        let v = root.as_dictionary()?.get(name)?;
        let v = match v.as_uid() {
            Some(uid) => objects.get(uid.get() as usize)?,
            None => v,
        };
        v.as_data()
    };
    let (Some(public), Some(private)) = (field("TSECKeyPairPublicKey"), field("TSECKeyPairPrivateKey")) else {
        return false;
    };
    match (
        PublicKey::from_djb_public_key_bytes(public),
        PrivateKey::deserialize(private),
    ) {
        (Ok(public), Ok(private)) => private.public_key().is_ok_and(|p| p == public),
        _ => false,
    }
}

pub fn inspect(path: &Path, key_spec: &[u8]) -> Result<LegacySummary, CoreError> {
    let db = db::open_legacy(path, key_spec)?;
    let account = "TSStorageUserAccountCollection";
    let string = |key| Ok::<_, CoreError>(value(&db, account, key)?.and_then(|(_, v)| v.into_string()));
    let count = |table| {
        db.query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get::<_, i64>(0))
            .map(|n| n as u64)
    };
    let identity = value(
        &db,
        "TSStorageManagerIdentityKeyStoreCollection",
        "TSStorageManagerIdentityKeyStoreIdentityKey",
    )?;
    Ok(LegacySummary {
        has_account: string("TSStorageRegisteredUUIDKey")?.is_some()
            && identity.is_some_and(|(objects, root)| is_key_pair(&objects, &root)),
        phone_number: string("TSStorageRegisteredNumberKey")?,
        device_id: value(&db, account, "TSAccountManager_DeviceId")?
            .and_then(|(_, v)| v.as_unsigned_integer())
            .and_then(|id| id.try_into().ok()),
        chats: count("model_TSThread")?,
        messages: count("model_TSInteraction")?,
    })
}

#[cfg(test)]
mod tests {
    use plist::{Dictionary, Uid};
    use rand::{TryRngCore as _, rngs::OsRng};

    use super::*;

    /// The layout `NSKeyedArchiver` writes. shortcut: hand-built, not produced by Foundation; confirm
    /// against a real database with `cargo run --example legacy_check`.
    fn archive(root: Value, class: Option<&str>) -> Vec<u8> {
        let mut objects = vec![Value::String("$null".into()), root];
        if let Some(class) = class {
            objects[1]
                .as_dictionary_mut()
                .unwrap()
                .insert("$class".into(), Value::Uid(Uid::new(2)));
            objects.push(Value::Dictionary(Dictionary::from_iter([(
                "$classname",
                Value::String(class.into()),
            )])));
        }
        let archive = Dictionary::from_iter([
            ("$version", Value::Integer(100000.into())),
            ("$archiver", Value::String("NSKeyedArchiver".into())),
            (
                "$top",
                Value::Dictionary(Dictionary::from_iter([("root", Value::Uid(Uid::new(1)))])),
            ),
            ("$objects", Value::Array(objects)),
        ]);
        let mut out = Vec::new();
        Value::Dictionary(archive).to_writer_binary(&mut out).unwrap();
        out
    }

    #[test]
    fn reads_account_from_swift_database() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("signal.sqlite");
        let key = [2u8; db::KEY_SPEC_LEN];
        let keys = libsignal_protocol::KeyPair::generate(&mut OsRng.unwrap_err());
        let pair = |private: Vec<u8>| {
            archive(
                Value::Dictionary(Dictionary::from_iter([
                    (
                        "TSECKeyPairPublicKey",
                        Value::Data(keys.public_key.public_key_bytes().to_vec()),
                    ),
                    ("TSECKeyPairPrivateKey", Value::Data(private)),
                ])),
                Some("SignalServiceKit.ECKeyPair"),
            )
        };
        {
            // DDL as in GRDBSchemaMigrator, reduced to what is read.
            let db = db::open_core(&path, &key).unwrap();
            db.execute_batch(
                "CREATE TABLE keyvalue (key TEXT NOT NULL, collection TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (key, collection));
                 CREATE TABLE model_TSThread (id INTEGER PRIMARY KEY);
                 CREATE TABLE model_TSInteraction (id INTEGER PRIMARY KEY);
                 INSERT INTO model_TSThread DEFAULT VALUES;
                 INSERT INTO model_TSInteraction DEFAULT VALUES; INSERT INTO model_TSInteraction DEFAULT VALUES;",
            )
            .unwrap();
            let put = |collection: &str, key: &str, value: &dyn rusqlite::ToSql| {
                db.execute(
                    "INSERT OR REPLACE INTO keyvalue VALUES (?2, ?1, ?3)",
                    rusqlite::params![collection, key, value],
                )
                .unwrap();
            };
            let account = "TSStorageUserAccountCollection";
            put(
                account,
                "TSStorageRegisteredUUIDKey",
                &archive(Value::String("0b7a0f1c-0000-4000-8000-000000000001".into()), None),
            );
            put(account, "TSStorageRegisteredNumberKey", &"+4915112345678");
            put(
                account,
                "TSAccountManager_DeviceId",
                &archive(Value::Integer(3.into()), None),
            );
            put(
                "TSStorageManagerIdentityKeyStoreCollection",
                "TSStorageManagerIdentityKeyStoreIdentityKey",
                &pair(keys.private_key.serialize()),
            );
        }
        let expected = LegacySummary {
            has_account: true,
            phone_number: Some("+4915112345678".into()),
            device_id: Some(3),
            chats: 1,
            messages: 2,
        };
        assert_eq!(inspect(&path, &key).unwrap(), expected);

        // A private key that does not match is not an account to take over.
        let other = libsignal_protocol::KeyPair::generate(&mut OsRng.unwrap_err());
        db::open_core(&path, &key)
            .unwrap()
            .execute(
                "UPDATE keyvalue SET value = ?1 WHERE key LIKE '%IdentityKey'",
                [pair(other.private_key.serialize())],
            )
            .unwrap();
        assert!(!inspect(&path, &key).unwrap().has_account);
        assert!(inspect(&path, &[3u8; db::KEY_SPEC_LEN]).is_err());
    }
}
