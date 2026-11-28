//! SQLCipher access with the parameters the Swift app uses (GRDBDatabaseStorageAdapter.prepareDatabase).

use std::path::Path;

use rusqlite::{Connection, OpenFlags};

use crate::CoreError;

/// 256-bit key followed by a 128-bit salt, as stored in the keychain.
pub const KEY_SPEC_LEN: usize = 48;

/// The core's own schema, one entry per version. Only ever append.
const MIGRATIONS: &[&str] = &[
    "
    CREATE TABLE kv (key TEXT PRIMARY KEY, value BLOB NOT NULL) WITHOUT ROWID;
    -- kind: 0 signed, 1 kyber last resort. identity: 0 ACI, 1 PNI.
    CREATE TABLE prekey (
        identity INTEGER NOT NULL, kind INTEGER NOT NULL, id INTEGER NOT NULL, record BLOB NOT NULL,
        PRIMARY KEY (identity, kind, id)
    ) WITHOUT ROWID;
",
    "
    -- Kinds in prekey: 2 one-time EC, 3 one-time Kyber (deleted when used).
    -- Remote identity keys, by service id: the same for every local identity and device.
    CREATE TABLE identity (address TEXT PRIMARY KEY, key BLOB NOT NULL) WITHOUT ROWID;
    CREATE TABLE session (
        identity INTEGER NOT NULL, address TEXT NOT NULL, device INTEGER NOT NULL, record BLOB NOT NULL,
        PRIMARY KEY (identity, address, device)
    ) WITHOUT ROWID;
    CREATE TABLE sender_key (
        address TEXT NOT NULL, device INTEGER NOT NULL, distribution_id BLOB NOT NULL, record BLOB NOT NULL,
        PRIMARY KEY (address, device, distribution_id)
    ) WITHOUT ROWID;
    -- A last-resort Kyber key is used once per base key; a second use is a replay (as in the Swift app).
    CREATE TABLE kyber_use (
        identity INTEGER NOT NULL, kyber_id INTEGER NOT NULL, signed_id INTEGER NOT NULL, base_key BLOB NOT NULL,
        PRIMARY KEY (identity, kyber_id, signed_id, base_key)
    ) WITHOUT ROWID;
",
    "
    -- People by service id, with what messages told about them.
    CREATE TABLE recipient (service_id TEXT PRIMARY KEY, e164 TEXT, profile_key BLOB, name TEXT) WITHOUT ROWID;
    -- A chat is either with one person (service_id) or a group (group_id, its 32-byte identifier).
    CREATE TABLE thread (
        id INTEGER PRIMARY KEY,
        service_id TEXT UNIQUE,
        group_id BLOB UNIQUE,
        title TEXT,
        last_at INTEGER NOT NULL DEFAULT 0,
        unread INTEGER NOT NULL DEFAULT 0,
        CHECK ((service_id IS NULL) != (group_id IS NULL))
    );
    -- author is '' for messages this account sent; (thread, author, sent_at) identifies a message, as in Signal.
    CREATE TABLE message (
        id INTEGER PRIMARY KEY,
        thread INTEGER NOT NULL REFERENCES thread (id),
        author TEXT NOT NULL,
        sent_at INTEGER NOT NULL,
        received_at INTEGER NOT NULL,
        body TEXT NOT NULL,
        UNIQUE (thread, author, sent_at)
    );
",
];

fn open(path: &Path, key_spec: &[u8], flags: OpenFlags) -> Result<Connection, CoreError> {
    if key_spec.len() != KEY_SPEC_LEN {
        return Err(CoreError::Database("unexpected key spec length".into()));
    }
    let db = Connection::open_with_flags(path, flags)?;
    db.execute_batch(&format!(
        "PRAGMA key = \"x'{}'\"; PRAGMA cipher_plaintext_header_size = 32;",
        hex::encode(key_spec)
    ))?;
    // A wrong key only fails on the first read.
    db.query_row("SELECT count(*) FROM sqlite_master", [], |_| Ok(()))
        .map_err(|_| CoreError::Database("wrong key or not a database".into()))?;
    Ok(db)
}

/// Opens the Swift app's database. Never writes to it.
pub fn open_legacy(path: &Path, key_spec: &[u8]) -> Result<Connection, CoreError> {
    let db = open(path, key_spec, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    db.pragma_update(None, "query_only", true)?;
    Ok(db)
}

/// Opens or creates the core's own database and brings its schema up to date.
pub fn open_core(path: &Path, key_spec: &[u8]) -> Result<Connection, CoreError> {
    let mut db = open(path, key_spec, OpenFlags::default())?;
    db.pragma_update(None, "journal_mode", "WAL")?;
    // Same durability as the Swift app; F_BARRIERFSYNC needs Signal's SQLCipher fork, which this build does not use.
    db.execute_batch("PRAGMA checkpoint_fullfsync = ON; PRAGMA fullfsync = ON;")?;
    let version = db.pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))? as usize;
    if version > MIGRATIONS.len() {
        return Err(CoreError::Database("database is from a newer version of Ivy".into()));
    }
    for (i, sql) in MIGRATIONS.iter().enumerate().skip(version) {
        let tx = db.transaction()?;
        tx.execute_batch(sql)?;
        tx.pragma_update(None, "user_version", i as u32 + 1)?;
        tx.commit()?;
    }
    Ok(db)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypted_with_plaintext_header_and_reopens() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("core.sqlite");
        let key = [7u8; KEY_SPEC_LEN];
        open_core(&path, &key)
            .unwrap()
            .execute("INSERT INTO kv VALUES ('a', x'01')", [])
            .unwrap();

        let bytes = std::fs::read(&path).unwrap();
        assert!(
            bytes.starts_with(b"SQLite format 3\0"),
            "iOS needs the plaintext header"
        );
        assert!(
            !bytes.windows(12).any(|w| w == b"CREATE TABLE"),
            "schema must be encrypted"
        );

        let n: i64 = open_core(&path, &key)
            .unwrap()
            .query_row("SELECT count(*) FROM kv", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 1);
        assert!(open_core(&path, &[8u8; KEY_SPEC_LEN]).is_err(), "wrong key");
        assert!(open_core(&path, &[7u8; 32]).is_err(), "short key");
    }

    #[test]
    fn legacy_is_read_only() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("signal.sqlite");
        let key = [1u8; KEY_SPEC_LEN];
        open_core(&path, &key).unwrap();
        let db = open_legacy(&path, &key).unwrap();
        assert!(db.execute("INSERT INTO kv VALUES ('a', x'01')", []).is_err());
    }
}
