//! libsignal's protocol stores on the core database, one per local identity (ACI or PNI).
// shortcut: only the tests use these until the receive step wires them in; drop this allow then.
#![cfg_attr(not(test), allow(dead_code))]

use async_trait::async_trait;
use libsignal_protocol::{
    Direction, GenericSignedPreKey, IdentityChange, IdentityKey, IdentityKeyPair, IdentityKeyStore, KyberPreKeyId,
    KyberPreKeyRecord, KyberPreKeyStore, PreKeyId, PreKeyRecord, PreKeyStore, ProtocolAddress, PublicKey,
    SenderKeyRecord, SenderKeyStore, SessionRecord, SessionStore, SignalProtocolError, SignedPreKeyId,
    SignedPreKeyRecord, SignedPreKeyStore,
};
use rusqlite::{Connection, OptionalExtension as _, params};
use uuid::Uuid;

type Result<T> = std::result::Result<T, SignalProtocolError>;

const SIGNED: u8 = 0;
const KYBER_LAST_RESORT: u8 = 1;
const ONE_TIME: u8 = 2;
const KYBER_ONE_TIME: u8 = 3;

pub const ACI: u8 = 0;

/// Cheap to clone: libsignal wants each store as a separate `&mut`, so callers pass clones.
#[derive(Clone)]
pub struct Store<'a> {
    pub db: &'a Connection,
    pub identity: u8,
    pub keys: IdentityKeyPair,
    pub registration_id: u32,
}

fn db_error(e: rusqlite::Error) -> SignalProtocolError {
    SignalProtocolError::InvalidState("database", e.to_string())
}

impl Store<'_> {
    fn prekey(&self, kinds: &[u8], id: u32) -> Result<Option<Vec<u8>>> {
        let mut found = None;
        for kind in kinds {
            found = self
                .db
                .query_row(
                    "SELECT record FROM prekey WHERE identity = ?1 AND kind = ?2 AND id = ?3",
                    params![self.identity, kind, id],
                    |r| r.get(0),
                )
                .optional()
                .map_err(db_error)?;
            if found.is_some() {
                break;
            }
        }
        Ok(found)
    }

    fn save_prekey(&self, kind: u8, id: u32, record: Vec<u8>) -> Result<()> {
        self.db
            .execute(
                "INSERT OR REPLACE INTO prekey VALUES (?1, ?2, ?3, ?4)",
                params![self.identity, kind, id, record],
            )
            .map(drop)
            .map_err(db_error)
    }
}

#[async_trait(?Send)]
impl IdentityKeyStore for Store<'_> {
    async fn get_identity_key_pair(&self) -> Result<IdentityKeyPair> {
        Ok(self.keys)
    }

    async fn get_local_registration_id(&self) -> Result<u32> {
        Ok(self.registration_id)
    }

    async fn save_identity(&mut self, address: &ProtocolAddress, identity: &IdentityKey) -> Result<IdentityChange> {
        let existing = self.get_identity(address).await?;
        if existing.as_ref() == Some(identity) {
            return Ok(IdentityChange::NewOrUnchanged);
        }
        self.db
            .execute(
                "INSERT OR REPLACE INTO identity VALUES (?1, ?2)",
                params![address.name(), identity.serialize().as_ref()],
            )
            .map_err(db_error)?;
        Ok(IdentityChange::from_changed(existing.is_some()))
    }

    async fn is_trusted_identity(
        &self,
        address: &ProtocolAddress,
        identity: &IdentityKey,
        direction: Direction,
    ) -> Result<bool> {
        Ok(match direction {
            // Incoming messages are always accepted; a changed key shows up as a safety number change.
            Direction::Receiving => true,
            // shortcut: refuses to send after any key change; the send slice adds Signal's acknowledge-and-send rule.
            Direction::Sending => self.get_identity(address).await?.is_none_or(|known| known == *identity),
        })
    }

    async fn get_identity(&self, address: &ProtocolAddress) -> Result<Option<IdentityKey>> {
        let key: Option<Vec<u8>> = self
            .db
            .query_row("SELECT key FROM identity WHERE address = ?1", [address.name()], |r| {
                r.get(0)
            })
            .optional()
            .map_err(db_error)?;
        key.map(|k| IdentityKey::decode(&k)).transpose()
    }
}

#[async_trait(?Send)]
impl PreKeyStore for Store<'_> {
    async fn get_pre_key(&self, id: PreKeyId) -> Result<PreKeyRecord> {
        let record = self
            .prekey(&[ONE_TIME], id.into())?
            .ok_or(SignalProtocolError::InvalidPreKeyId)?;
        PreKeyRecord::deserialize(&record)
    }

    async fn save_pre_key(&mut self, id: PreKeyId, record: &PreKeyRecord) -> Result<()> {
        self.save_prekey(ONE_TIME, id.into(), record.serialize()?)
    }

    async fn remove_pre_key(&mut self, id: PreKeyId) -> Result<()> {
        self.db
            .execute(
                "DELETE FROM prekey WHERE identity = ?1 AND kind = ?2 AND id = ?3",
                params![self.identity, ONE_TIME, u32::from(id)],
            )
            .map(drop)
            .map_err(db_error)
    }
}

#[async_trait(?Send)]
impl SignedPreKeyStore for Store<'_> {
    async fn get_signed_pre_key(&self, id: SignedPreKeyId) -> Result<SignedPreKeyRecord> {
        let record = self
            .prekey(&[SIGNED], id.into())?
            .ok_or(SignalProtocolError::InvalidSignedPreKeyId)?;
        SignedPreKeyRecord::deserialize(&record)
    }

    async fn save_signed_pre_key(&mut self, id: SignedPreKeyId, record: &SignedPreKeyRecord) -> Result<()> {
        self.save_prekey(SIGNED, id.into(), record.serialize()?)
    }
}

#[async_trait(?Send)]
impl KyberPreKeyStore for Store<'_> {
    async fn get_kyber_pre_key(&self, id: KyberPreKeyId) -> Result<KyberPreKeyRecord> {
        let record = self
            .prekey(&[KYBER_ONE_TIME, KYBER_LAST_RESORT], id.into())?
            .ok_or(SignalProtocolError::InvalidKyberPreKeyId)?;
        KyberPreKeyRecord::deserialize(&record)
    }

    async fn save_kyber_pre_key(&mut self, id: KyberPreKeyId, record: &KyberPreKeyRecord) -> Result<()> {
        self.save_prekey(KYBER_ONE_TIME, id.into(), record.serialize()?)
    }

    async fn mark_kyber_pre_key_used(
        &mut self,
        id: KyberPreKeyId,
        signed_id: SignedPreKeyId,
        base_key: &PublicKey,
    ) -> Result<()> {
        let id = u32::from(id);
        let one_time = self
            .db
            .execute(
                "DELETE FROM prekey WHERE identity = ?1 AND kind = ?2 AND id = ?3",
                params![self.identity, KYBER_ONE_TIME, id],
            )
            .map_err(db_error)?;
        if one_time == 0 {
            // No OR IGNORE: the constraint failure is what rejects a replayed message.
            self.db
                .execute(
                    "INSERT INTO kyber_use VALUES (?1, ?2, ?3, ?4)",
                    params![self.identity, id, u32::from(signed_id), base_key.serialize().as_ref()],
                )
                .map_err(|_| SignalProtocolError::InvalidState("kyber", "last-resort key reused".into()))?;
        }
        Ok(())
    }
}

#[async_trait(?Send)]
impl SessionStore for Store<'_> {
    async fn load_session(&self, address: &ProtocolAddress) -> Result<Option<SessionRecord>> {
        let record: Option<Vec<u8>> = self
            .db
            .query_row(
                "SELECT record FROM session WHERE identity = ?1 AND address = ?2 AND device = ?3",
                params![self.identity, address.name(), u32::from(address.device_id())],
                |r| r.get(0),
            )
            .optional()
            .map_err(db_error)?;
        record.map(|r| SessionRecord::deserialize(&r)).transpose()
    }

    async fn store_session(&mut self, address: &ProtocolAddress, record: &SessionRecord) -> Result<()> {
        self.db
            .execute(
                "INSERT OR REPLACE INTO session VALUES (?1, ?2, ?3, ?4)",
                params![
                    self.identity,
                    address.name(),
                    u32::from(address.device_id()),
                    record.serialize()?
                ],
            )
            .map(drop)
            .map_err(db_error)
    }
}

#[async_trait(?Send)]
impl SenderKeyStore for Store<'_> {
    async fn store_sender_key(&mut self, sender: &ProtocolAddress, id: Uuid, record: &SenderKeyRecord) -> Result<()> {
        self.db
            .execute(
                "INSERT OR REPLACE INTO sender_key VALUES (?1, ?2, ?3, ?4)",
                params![
                    sender.name(),
                    u32::from(sender.device_id()),
                    id.as_bytes(),
                    record.serialize()?
                ],
            )
            .map(drop)
            .map_err(db_error)
    }

    async fn load_sender_key(&mut self, sender: &ProtocolAddress, id: Uuid) -> Result<Option<SenderKeyRecord>> {
        let record: Option<Vec<u8>> = self
            .db
            .query_row(
                "SELECT record FROM sender_key WHERE address = ?1 AND device = ?2 AND distribution_id = ?3",
                params![sender.name(), u32::from(sender.device_id()), id.as_bytes()],
                |r| r.get(0),
            )
            .optional()
            .map_err(db_error)?;
        record.map(|r| SenderKeyRecord::deserialize(&r)).transpose()
    }
}

#[cfg(test)]
mod tests {
    use std::time::SystemTime;

    use libsignal_protocol::{
        CiphertextMessage, DeviceId, InMemSignalProtocolStore, PreKeyBundle, PreKeySignalMessage,
        message_decrypt_prekey, message_encrypt, process_prekey_bundle,
    };
    use rand::{TryRngCore as _, rngs::OsRng};

    use super::*;
    use crate::{account, db, provisioning::LinkKeys};

    /// A message from someone who fetched our link-time bundle decrypts once, and a replay fails.
    #[tokio::test]
    async fn decrypts_first_message_and_rejects_replay() {
        let mut rng = OsRng.unwrap_err();
        let dir = tempfile::tempdir().unwrap();
        let mut conn = db::open_core(&dir.path().join("core.sqlite"), &[9; db::KEY_SPEC_LEN]).unwrap();
        let ours = IdentityKeyPair::generate(&mut rng);
        let keys = LinkKeys::generate(&ours);
        let account = account::tests::account(keys.registration_id);
        account::save(&mut conn, &account, &keys, None).unwrap();
        let store = Store {
            db: &conn,
            identity: ACI,
            keys: ours,
            registration_id: keys.registration_id,
        };

        let device = DeviceId::new(2).unwrap();
        let us = ProtocolAddress::new("our-aci".into(), device);
        let alice = ProtocolAddress::new("alice-aci".into(), DeviceId::new(1).unwrap());
        let mut theirs = InMemSignalProtocolStore::new(IdentityKeyPair::generate(&mut rng), 7).unwrap();
        let bundle = PreKeyBundle::new(
            keys.registration_id,
            device,
            None,
            keys.signed.id().unwrap(),
            keys.signed.public_key().unwrap(),
            keys.signed.signature().unwrap(),
            keys.last_resort.id().unwrap(),
            keys.last_resort.public_key().unwrap(),
            keys.last_resort.signature().unwrap(),
            *ours.identity_key(),
        )
        .unwrap();
        process_prekey_bundle(
            &us,
            &alice,
            &mut theirs.session_store,
            &mut theirs.identity_store,
            &bundle,
            SystemTime::now(),
            &mut rng,
        )
        .await
        .unwrap();
        let sent = message_encrypt(
            b"hello",
            &us,
            &alice,
            &mut theirs.session_store,
            &mut theirs.identity_store,
            SystemTime::now(),
            &mut rng,
        )
        .await
        .unwrap();
        let CiphertextMessage::PreKeySignalMessage(sent) = sent else {
            panic!("first message is a prekey message")
        };
        let bytes = sent.serialized().to_vec();

        let decrypt = |bytes: Vec<u8>| {
            let (mut a, mut b, mut c, d, mut e) = (
                store.clone(),
                store.clone(),
                store.clone(),
                store.clone(),
                store.clone(),
            );
            let (alice, us) = (alice.clone(), us.clone());
            async move {
                let message = PreKeySignalMessage::try_from(bytes.as_slice()).unwrap();
                message_decrypt_prekey(
                    &message,
                    &alice,
                    &us,
                    &mut a,
                    &mut b,
                    &mut c,
                    &d,
                    &mut e,
                    &mut OsRng.unwrap_err(),
                )
                .await
            }
        };
        assert_eq!(decrypt(bytes.clone()).await.unwrap(), b"hello");
        assert!(
            store.get_identity(&alice).await.unwrap().is_some(),
            "sender's identity is remembered"
        );
        // The session exists now, so the same message is a duplicate; with the session gone, the
        // last-resort key's use record still refuses it.
        assert!(decrypt(bytes.clone()).await.is_err());
        conn.execute("DELETE FROM session", []).unwrap();
        assert!(decrypt(bytes).await.is_err());
    }
}
