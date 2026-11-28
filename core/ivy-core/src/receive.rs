//! Receiving: decrypting what the server delivers and storing the messages it carries.

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use futures_util::FutureExt as _;
use libsignal_core::ServiceId;
use libsignal_protocol::{
    CiphertextMessageType, DeviceId, IdentityKeyPair, PreKeySignalMessage, ProtocolAddress, PublicKey,
    SenderKeyDistributionMessage, SignalMessage, SignalProtocolError, Timestamp, group_decrypt, message_decrypt_prekey,
    message_decrypt_signal, process_sender_key_distribution_message, sealed_sender_decrypt_to_usmc,
};
use prost::Message as _;
use rand::{TryRngCore as _, rngs::OsRng};
use rusqlite::{Connection, params};
use zkgroup::groups::{GroupMasterKey, GroupSecretParams};

use crate::CoreError;
use crate::account::Account;
use crate::proto::service::{Content, DataMessage, Envelope, envelope};
use crate::store::{self, Store};

/// Signal's production sealed sender trust roots, as in the Swift app (TSConstants.kUDTrustRoots).
const TRUST_ROOTS: [&str; 2] = [
    "BXu6QIKVz5MA8gstzfOgRQGqyLqOwNKHL6INkv3IHWMF",
    "BUkY0I+9+oPgDCn4+Ac6Iu813yvqkDr/ga8DzLxFxuk6",
];

pub fn trust_roots() -> Vec<PublicKey> {
    TRUST_ROOTS
        .iter()
        .map(|key| PublicKey::deserialize(&STANDARD.decode(key).expect("base64")).expect("valid key"))
        .collect()
}

/// The stores only touch SQLite, so libsignal's futures finish without waiting.
fn now<T>(future: impl Future<Output = T>) -> T {
    future.now_or_never().expect("the stores never wait")
}

fn service_id(binary: Option<&[u8]>, text: Option<&str>) -> Option<ServiceId> {
    binary
        .and_then(ServiceId::parse_from_service_id_binary)
        .or_else(|| text.and_then(ServiceId::parse_from_service_id_string))
}

/// Who sent a decrypted message, and its `Content`.
struct Decrypted {
    sender: ProtocolAddress,
    e164: Option<String>,
    content: Vec<u8>,
}

fn local_store<'a>(db: &'a Connection, account: &Account, pni: bool) -> Result<Store<'a>, CoreError> {
    let invalid = || CoreError::Database("account keys".into());
    let (identity, keys, registration_id) = match pni {
        false => (store::ACI, &account.aci_identity, account.aci_registration_id),
        true => (
            store::PNI,
            account.pni_identity.as_ref().ok_or_else(invalid)?,
            account.pni_registration_id.ok_or_else(invalid)?,
        ),
    };
    let keys = IdentityKeyPair::try_from(keys.as_slice()).map_err(|_| invalid())?;
    Ok(Store {
        db,
        identity,
        keys,
        registration_id,
    })
}

fn decrypt_session(
    store: &Store,
    kind: CiphertextMessageType,
    bytes: &[u8],
    sender: &ProtocolAddress,
    local: &ProtocolAddress,
) -> Result<Vec<u8>, SignalProtocolError> {
    let mut rng = OsRng.unwrap_err();
    let (mut a, mut b, mut c, d, mut e) = (
        store.clone(),
        store.clone(),
        store.clone(),
        store.clone(),
        store.clone(),
    );
    match kind {
        CiphertextMessageType::Whisper => now(message_decrypt_signal(
            &SignalMessage::try_from(bytes)?,
            sender,
            local,
            &mut a,
            &mut b,
            &mut rng,
        )),
        CiphertextMessageType::PreKey => now(message_decrypt_prekey(
            &PreKeySignalMessage::try_from(bytes)?,
            sender,
            local,
            &mut a,
            &mut b,
            &mut c,
            &d,
            &mut e,
            &mut rng,
        )),
        CiphertextMessageType::SenderKey => now(group_decrypt(bytes, &mut a, sender)),
        other => Err(SignalProtocolError::InvalidMessage(
            other,
            "not a message with content".into(),
        )),
    }
}

/// `Ok(None)` for envelopes without a message: receipts, decryption errors, our own sealed sends.
fn decrypt(
    store: &Store,
    account: &Account,
    envelope: &Envelope,
    local: &ProtocolAddress,
    server_time: Timestamp,
    roots: &[PublicKey],
) -> Result<Option<Decrypted>, SignalProtocolError> {
    let bytes = envelope.content.as_deref().unwrap_or_default();
    let session_kind = match envelope.r#type() {
        envelope::Type::Ciphertext => Some(CiphertextMessageType::Whisper),
        envelope::Type::PrekeyBundle => Some(CiphertextMessageType::PreKey),
        envelope::Type::UnidentifiedSender => None,
        _ => return Ok(None),
    };
    if let Some(kind) = session_kind {
        let source = service_id(
            envelope.source_service_id_binary.as_deref(),
            envelope.source_service_id.as_deref(),
        )
        .ok_or_else(|| SignalProtocolError::InvalidArgument("envelope without a sender".into()))?;
        let device = DeviceId::try_from(envelope.source_device())
            .map_err(|_| SignalProtocolError::InvalidArgument("bad sender device".into()))?;
        let sender = ProtocolAddress::new(source.service_id_string(), device);
        let content = decrypt_session(store, kind, bytes, &sender, local)?;
        return Ok(Some(Decrypted {
            sender,
            e164: None,
            content,
        }));
    }

    let usmc = now(sealed_sender_decrypt_to_usmc(bytes, store))?;
    let certificate = usmc.sender()?;
    // Checked against every root, so which one signed isn't revealed by timing.
    if !certificate.validate_with_trust_roots(roots, server_time)? {
        return Err(SignalProtocolError::InvalidSealedSenderMessage(
            "not signed by a trust root".into(),
        ));
    }
    let sender = ProtocolAddress::new(certificate.sender_uuid()?.to_owned(), certificate.sender_device_id()?);
    if sender.name() == account.aci && u32::from(sender.device_id()) == account.device_id {
        return Ok(None);
    }
    let e164 = certificate.sender_e164()?.map(str::to_owned);
    match usmc.msg_type()? {
        CiphertextMessageType::Plaintext => Ok(None),
        kind => {
            let content = decrypt_session(store, kind, usmc.contents()?, &sender, local)?;
            Ok(Some(Decrypted { sender, e164, content }))
        }
    }
}

/// Signal pads content with 0x80 and zeros.
fn unpad(mut bytes: Vec<u8>) -> Vec<u8> {
    if let Some(end) = bytes.iter().rposition(|&b| b != 0)
        && bytes[end] == 0x80
    {
        bytes.truncate(end);
    }
    bytes
}

enum Chat {
    Contact(String),
    Group([u8; 32]),
}

fn group_of(message: &DataMessage) -> Option<Chat> {
    let key: [u8; 32] = message.group_v2.as_ref()?.master_key.as_deref()?.try_into().ok()?;
    let id = GroupSecretParams::derive_from_master_key(GroupMasterKey::new(key)).get_group_identifier();
    Some(Chat::Group(id))
}

fn thread_id(db: &Connection, chat: &Chat) -> rusqlite::Result<i64> {
    let (column, value): (&str, rusqlite::types::Value) = match chat {
        Chat::Contact(id) => ("service_id", id.clone().into()),
        Chat::Group(id) => ("group_id", id.to_vec().into()),
    };
    db.execute(
        &format!("INSERT OR IGNORE INTO thread ({column}) VALUES (?1)"),
        [&value],
    )?;
    db.query_row(&format!("SELECT id FROM thread WHERE {column} = ?1"), [&value], |r| {
        r.get(0)
    })
}

/// Stores a message once; true when it is new.
fn save_message(
    db: &Connection,
    chat: &Chat,
    author: &str,
    message: &DataMessage,
    sent_at: u64,
) -> rusqlite::Result<bool> {
    // shortcut: reactions, deletes, edits and other updates are not shown yet; the read slice adds them.
    let body = message.body.clone().unwrap_or_default();
    if body.is_empty() && message.attachments.is_empty() && message.sticker.is_none() {
        return Ok(false);
    }
    let thread = thread_id(db, chat)?;
    let received_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let added = db.execute(
        "INSERT OR IGNORE INTO message (thread, author, sent_at, received_at, body) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![thread, author, sent_at as i64, received_at, body],
    )? == 1;
    if added {
        db.execute(
            "UPDATE thread SET last_at = max(last_at, ?2), unread = unread + ?3 WHERE id = ?1",
            params![thread, sent_at as i64, !author.is_empty()],
        )?;
    }
    Ok(added)
}

fn remember(db: &Connection, sender: &str, e164: Option<&str>, profile_key: Option<&[u8]>) -> rusqlite::Result<()> {
    db.execute("INSERT OR IGNORE INTO recipient (service_id) VALUES (?1)", [sender])?;
    if let Some(e164) = e164 {
        db.execute(
            "UPDATE recipient SET e164 = ?2 WHERE service_id = ?1",
            params![sender, e164],
        )?;
    }
    if let Some(key) = profile_key.filter(|k| k.len() == 32) {
        db.execute(
            "UPDATE recipient SET profile_key = ?2 WHERE service_id = ?1",
            params![sender, key],
        )?;
    }
    Ok(())
}

/// Decrypts one envelope and stores what it says. True when the conversation list changed.
/// Errors are logged and swallowed: the envelope is acknowledged either way, or the server
/// would deliver it again forever.
pub fn process(
    db: &Connection,
    account: &Account,
    envelope: &[u8],
    server_time: Timestamp,
    roots: &[PublicKey],
) -> bool {
    match try_process(db, account, envelope, server_time, roots) {
        Ok(changed) => changed,
        Err(e) => {
            // shortcut: no retry receipt is sent, so the sender doesn't resend; add with the send slice.
            log::warn!("dropped an envelope: {e}");
            false
        }
    }
}

fn try_process(
    db: &Connection,
    account: &Account,
    bytes: &[u8],
    server_time: Timestamp,
    roots: &[PublicKey],
) -> Result<bool, CoreError> {
    let envelope = Envelope::decode(bytes).map_err(|e| CoreError::Network(format!("envelope: {e}")))?;
    let destination = service_id(
        envelope.destination_service_id_binary.as_deref(),
        envelope.destination_service_id.as_deref(),
    );
    let pni = matches!(destination, Some(ServiceId::Pni(_))) && account.pni.is_some();
    let store = local_store(db, account, pni)?;
    let local_name = if pni {
        account.pni.clone().unwrap_or_default()
    } else {
        account.aci.clone()
    };
    let local = ProtocolAddress::new(
        local_name,
        DeviceId::try_from(account.device_id).map_err(|_| CoreError::InvalidProvisioning)?,
    );
    let protocol_error = |e: SignalProtocolError| CoreError::Network(format!("decrypt: {e}"));

    let tx = db.unchecked_transaction()?;
    let Some(decrypted) = decrypt(&store, account, &envelope, &local, server_time, roots).map_err(protocol_error)?
    else {
        return Ok(false);
    };
    let content = Content::decode(unpad(decrypted.content).as_slice())
        .map_err(|e| CoreError::Network(format!("content: {e}")))?;
    let sender = decrypted.sender.name().to_owned();
    if let Some(skdm) = content.sender_key_distribution_message.as_deref() {
        let skdm = SenderKeyDistributionMessage::try_from(skdm).map_err(protocol_error)?;
        let mut keys = store.clone();
        now(process_sender_key_distribution_message(
            &decrypted.sender,
            &skdm,
            &mut keys,
        ))
        .map_err(protocol_error)?;
    }

    let mut changed = false;
    if sender == account.aci {
        // Sent from this account's other devices.
        if let Some(sent) = content.sync_message.and_then(|s| s.sent)
            && let Some(message) = sent.message.as_ref()
        {
            let chat = group_of(message).or_else(|| {
                service_id(
                    sent.destination_service_id_binary.as_deref(),
                    sent.destination_service_id.as_deref(),
                )
                .map(|id| Chat::Contact(id.service_id_string()))
            });
            if let Some(chat) = chat {
                changed = save_message(
                    db,
                    &chat,
                    "",
                    message,
                    sent.timestamp.or(message.timestamp).unwrap_or_default(),
                )?;
            }
        }
    } else if let Some(message) = content.data_message.as_ref() {
        remember(db, &sender, decrypted.e164.as_deref(), message.profile_key.as_deref())?;
        let chat = group_of(message).unwrap_or(Chat::Contact(sender.clone()));
        changed = save_message(
            db,
            &chat,
            &sender,
            message,
            message.timestamp.or(envelope.timestamp).unwrap_or_default(),
        )?;
    }
    tx.commit()?;
    Ok(changed)
}

/// One row of the conversation list.
#[derive(uniffi::Record, Debug, PartialEq)]
pub struct Conversation {
    pub id: i64,
    /// The contact's name or number, or the group's name; absent when not known yet.
    pub title: Option<String>,
    pub is_group: bool,
    /// The newest message's text; empty for a message with only attachments.
    pub snippet: String,
    pub timestamp_ms: u64,
    pub unread: u32,
}

pub fn conversations(db: &Connection) -> rusqlite::Result<Vec<Conversation>> {
    let mut query = db.prepare(
        "SELECT t.id, coalesce(t.title, r.name, r.e164), t.group_id IS NOT NULL, t.last_at, t.unread,
                (SELECT body FROM message m WHERE m.thread = t.id ORDER BY m.sent_at DESC LIMIT 1)
         FROM thread t LEFT JOIN recipient r ON r.service_id = t.service_id
         ORDER BY t.last_at DESC",
    )?;
    query
        .query_map([], |r| {
            Ok(Conversation {
                id: r.get(0)?,
                title: r.get(1)?,
                is_group: r.get(2)?,
                timestamp_ms: r.get::<_, i64>(3)? as u64,
                unread: r.get(4)?,
                snippet: r.get::<_, Option<String>>(5)?.unwrap_or_default(),
            })
        })?
        .collect()
}

#[cfg(test)]
mod tests {
    use std::time::SystemTime;

    use libsignal_protocol::{
        CiphertextMessage, GenericSignedPreKey as _, InMemSignalProtocolStore, KeyPair, PreKeyBundle,
        SenderCertificate, ServerCertificate, message_encrypt, process_prekey_bundle, sealed_sender_encrypt,
    };

    use super::*;
    use crate::proto::service::{GroupContextV2, SyncMessage, sync_message};
    use crate::{account, db, provisioning::LinkKeys};

    const OURS: &str = "00000000-0000-4000-8000-0000000000aa";
    const ALICE: &str = "00000000-0000-4000-8000-0000000000a1";
    const BOB: &str = "00000000-0000-4000-8000-0000000000b0";

    struct Us {
        _dir: tempfile::TempDir,
        db: Connection,
        account: Account,
        identity: IdentityKeyPair,
        keys: LinkKeys,
    }

    fn us() -> Us {
        let dir = tempfile::tempdir().unwrap();
        let mut db = db::open_core(&dir.path().join("core.sqlite"), &[4; db::KEY_SPEC_LEN]).unwrap();
        let identity = IdentityKeyPair::generate(&mut OsRng.unwrap_err());
        let keys = LinkKeys::generate(&identity);
        let mut account = account::tests::account(keys.registration_id);
        account.aci = OURS.into();
        account.aci_identity = identity.serialize().into_vec();
        account::save(&mut db, &account, &keys, None).unwrap();
        Us {
            _dir: dir,
            db,
            account,
            identity,
            keys,
        }
    }

    /// Someone (`name`, device 1, with `identity`) who fetched our link-time bundle.
    async fn sender(us: &Us, name: &str, identity: IdentityKeyPair) -> InMemSignalProtocolStore {
        let mut store = InMemSignalProtocolStore::new(identity, 9).unwrap();
        let bundle = PreKeyBundle::new(
            us.keys.registration_id,
            DeviceId::new(2).unwrap(),
            None,
            us.keys.signed.id().unwrap(),
            us.keys.signed.public_key().unwrap(),
            us.keys.signed.signature().unwrap(),
            us.keys.last_resort.id().unwrap(),
            us.keys.last_resort.public_key().unwrap(),
            us.keys.last_resort.signature().unwrap(),
            *us.identity.identity_key(),
        )
        .unwrap();
        let (to, from) = (address(OURS, 2), address(name, 1));
        process_prekey_bundle(
            &to,
            &from,
            &mut store.session_store,
            &mut store.identity_store,
            &bundle,
            SystemTime::now(),
            &mut OsRng.unwrap_err(),
        )
        .await
        .unwrap();
        store
    }

    fn address(name: &str, device: u8) -> ProtocolAddress {
        ProtocolAddress::new(name.into(), DeviceId::new(device).unwrap())
    }

    fn padded(content: &Content) -> Vec<u8> {
        let mut bytes = content.encode_to_vec();
        bytes.push(0x80);
        bytes.resize(bytes.len().div_ceil(160) * 160, 0);
        bytes
    }

    fn text(body: &str, sent_at: u64) -> DataMessage {
        DataMessage {
            body: Some(body.into()),
            timestamp: Some(sent_at),
            ..Default::default()
        }
    }

    async fn session_envelope(store: &mut InMemSignalProtocolStore, from: &str, content: &Content) -> Vec<u8> {
        let message = message_encrypt(
            &padded(content),
            &address(OURS, 2),
            &address(from, 1),
            &mut store.session_store,
            &mut store.identity_store,
            SystemTime::now(),
            &mut OsRng.unwrap_err(),
        )
        .await
        .unwrap();
        let kind = match message {
            CiphertextMessage::PreKeySignalMessage(_) => envelope::Type::PrekeyBundle,
            _ => envelope::Type::Ciphertext,
        };
        Envelope {
            r#type: Some(kind as i32),
            source_service_id: Some(from.into()),
            source_device: Some(1),
            destination_service_id: Some(OURS.into()),
            timestamp: Some(1),
            content: Some(message.serialize().to_vec()),
            ..Default::default()
        }
        .encode_to_vec()
    }

    fn time() -> Timestamp {
        Timestamp::from_epoch_millis(1_800_000_000_000)
    }

    #[tokio::test]
    async fn message_from_a_contact_starts_a_conversation() {
        let us = us();
        let mut alice = sender(&us, ALICE, IdentityKeyPair::generate(&mut OsRng.unwrap_err())).await;
        let content = Content {
            data_message: Some(text("hi", 1_700_000_000_000)),
            ..Default::default()
        };
        let envelope = session_envelope(&mut alice, ALICE, &content).await;

        assert!(process(&us.db, &us.account, &envelope, time(), &trust_roots()));
        let expected = Conversation {
            id: 1,
            title: None,
            is_group: false,
            snippet: "hi".into(),
            timestamp_ms: 1_700_000_000_000,
            unread: 1,
        };
        assert_eq!(conversations(&us.db).unwrap(), vec![expected]);
        // Delivered twice: stored once.
        assert!(!process(&us.db, &us.account, &envelope, time(), &trust_roots()));
        assert_eq!(conversations(&us.db).unwrap()[0].unread, 1);
    }

    #[tokio::test]
    async fn sealed_group_message_checks_the_trust_root() {
        let us = us();
        let mut rng = OsRng.unwrap_err();
        let alice_identity = IdentityKeyPair::generate(&mut rng);
        let mut alice = sender(&us, ALICE, alice_identity).await;
        let (root, server) = (KeyPair::generate(&mut rng), KeyPair::generate(&mut rng));
        let server_cert = ServerCertificate::new(1, server.public_key, &root.private_key, &mut rng).unwrap();
        let certificate = SenderCertificate::new(
            ALICE.into(),
            Some("+4915112345678".into()),
            *alice_identity.public_key(),
            DeviceId::new(1).unwrap(),
            Timestamp::from_epoch_millis(u64::MAX / 2),
            server_cert,
            &server.private_key,
            &mut rng,
        )
        .unwrap();
        let mut message = text("in the group", 1_700_000_000_001);
        message.group_v2 = Some(GroupContextV2 {
            master_key: Some(vec![7; 32]),
            revision: Some(1),
            group_change: None,
        });
        let sealed = sealed_sender_encrypt(
            &address(OURS, 2),
            &certificate,
            &padded(&Content {
                data_message: Some(message),
                ..Default::default()
            }),
            &mut alice.session_store,
            &mut alice.identity_store,
            SystemTime::now(),
            &mut rng,
        )
        .await
        .unwrap();
        let envelope = Envelope {
            r#type: Some(envelope::Type::UnidentifiedSender as i32),
            destination_service_id: Some(OURS.into()),
            content: Some(sealed),
            ..Default::default()
        }
        .encode_to_vec();

        // Not signed by Signal's roots: dropped.
        assert!(!process(&us.db, &us.account, &envelope, time(), &trust_roots()));
        assert!(process(&us.db, &us.account, &envelope, time(), &[root.public_key]));
        let list = conversations(&us.db).unwrap();
        assert_eq!(
            (list.len(), list[0].is_group, list[0].snippet.as_str()),
            (1, true, "in the group")
        );
        // The certificate's number names the sender for later.
        let e164: String = us.db.query_row("SELECT e164 FROM recipient", [], |r| r.get(0)).unwrap();
        assert_eq!(e164, "+4915112345678");
    }

    #[tokio::test]
    async fn message_sent_from_the_phone_is_ours_and_read() {
        let us = us();
        // The phone is this account's device 1, with the same identity.
        let mut phone = sender(&us, OURS, us.identity).await;
        let sent = sync_message::Sent {
            destination_service_id: Some(BOB.into()),
            timestamp: Some(1_700_000_000_002),
            message: Some(text("see you", 1_700_000_000_002)),
            ..Default::default()
        };
        let content = Content {
            sync_message: Some(SyncMessage {
                sent: Some(sent),
                ..Default::default()
            }),
            ..Default::default()
        };
        let envelope = session_envelope(&mut phone, OURS, &content).await;

        assert!(process(&us.db, &us.account, &envelope, time(), &trust_roots()));
        let list = conversations(&us.db).unwrap();
        assert_eq!((list[0].snippet.as_str(), list[0].unread), ("see you", 0));
        let thread: String = us
            .db
            .query_row("SELECT service_id FROM thread", [], |r| r.get(0))
            .unwrap();
        assert_eq!(thread, BOB);
    }
}
