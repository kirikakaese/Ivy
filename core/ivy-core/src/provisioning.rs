//! Linking as a secondary device: the QR link, the primary's encrypted message, and the link request.
//! Behaviour follows ProvisioningCipher, LinkingProvisioningMessage, OWSDeviceNames and
//! ProvisioningRequestFactory in the Swift app.

use base64::Engine as _;
use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD};
use hkdf::Hkdf;
use libsignal_core::{Aci, Pni};
use libsignal_protocol::{
    GenericSignedPreKey, IdentityKey, IdentityKeyPair, KeyPair, KyberPreKeyRecord, PrivateKey, PublicKey,
    SignedPreKeyRecord, Timestamp, kem,
};
use prost::Message as _;
use rand::{Rng as _, TryRngCore as _, rngs::OsRng};
use serde_json::{Value, json};
use sha2::Sha256;
use signal_crypto::{Aes256Ctr32, CryptographicMac, aes_256_cbc_decrypt};
use subtle::ConstantTimeEq as _;

use crate::CoreError;
use crate::proto::{DeviceName, ProvisionEnvelope, ProvisionMessage};

const INVALID: CoreError = CoreError::InvalidProvisioning;

/// `sgnl://linkdevice` URL the primary scans. Built by hand: Android does not accept '+' and '/' unescaped.
pub fn link_url(address: &str, our_public: &PublicKey) -> String {
    let key = STANDARD
        .encode(our_public.serialize())
        .replace('+', "%2B")
        .replace('/', "%2F")
        .replace('=', "%3D");
    // shortcut: no capabilities, so the primary offers no message history transfer; add "backup5" with the backups slice.
    format!("sgnl://linkdevice?uuid={address}&pub_key={key}&capabilities=")
}

fn hmac(key: &[u8], data: &[u8]) -> Vec<u8> {
    CryptographicMac::new("HmacSha256", key)
        .expect("valid algorithm")
        .update_and_get(data)
        .finalize()
}

fn cipher_and_mac_key(ours: &PrivateKey, theirs: &PublicKey) -> Result<[u8; 64], CoreError> {
    let secret = ours.calculate_agreement(theirs).map_err(|_| INVALID)?;
    let mut keys = [0u8; 64];
    Hkdf::<Sha256>::new(None, &secret)
        .expand(b"TextSecure Provisioning Message", &mut keys)
        .expect("valid length");
    Ok(keys)
}

/// What the primary device hands over, validated.
pub struct Provisioned {
    pub aci: Aci,
    pub aci_identity: IdentityKeyPair,
    /// Number, PNI and PNI identity; absent on accounts without a phone number.
    pub phone: Option<(String, Pni, IdentityKeyPair)>,
    pub auth_credential_salt: Option<Vec<u8>>,
    pub profile_key: [u8; 32],
    pub account_entropy_pool: String,
    pub media_root_backup_key: [u8; 32],
    pub read_receipts: bool,
    pub code: String,
}

fn identity(public: Option<&[u8]>, private: Option<&[u8]>) -> Result<IdentityKeyPair, CoreError> {
    let public = PublicKey::deserialize(public.ok_or(INVALID)?).map_err(|_| INVALID)?;
    let private = PrivateKey::deserialize(private.ok_or(INVALID)?).map_err(|_| INVALID)?;
    // Stricter than the Swift app: a mismatched pair would only fail later, when signing.
    if private.public_key().map_err(|_| INVALID)? != public {
        return Err(INVALID);
    }
    Ok(IdentityKeyPair::new(IdentityKey::new(public), private))
}

fn exact<const N: usize>(bytes: Option<&[u8]>) -> Result<[u8; N], CoreError> {
    bytes.ok_or(INVALID)?.try_into().map_err(|_| INVALID)
}

/// Authenticates and decrypts a `ProvisionEnvelope`: version 1 || IV || AES-256-CBC || HMAC-SHA256.
pub fn decrypt_envelope(ours: &PrivateKey, envelope: &[u8]) -> Result<Provisioned, CoreError> {
    let envelope = ProvisionEnvelope::decode(envelope).map_err(|_| INVALID)?;
    let theirs = PublicKey::deserialize(envelope.public_key.as_deref().ok_or(INVALID)?).map_err(|_| INVALID)?;
    let body = envelope.body.as_deref().ok_or(INVALID)?;
    if body.len() < 1 + 16 + 16 + 32 || body[0] != 1 {
        return Err(INVALID);
    }
    let (signed, their_mac) = body.split_at(body.len() - 32);
    let keys = cipher_and_mac_key(ours, &theirs)?;
    if !bool::from(hmac(&keys[32..], signed).ct_eq(their_mac)) {
        return Err(INVALID);
    }
    let plaintext = aes_256_cbc_decrypt(&signed[17..], &keys[..32], &signed[1..17]).map_err(|_| INVALID)?;
    let m = ProvisionMessage::decode(plaintext.as_slice()).map_err(|_| INVALID)?;

    let phone = match &m.number {
        Some(number) => {
            let digits = number.strip_prefix('+').ok_or(INVALID)?;
            if !(7..=15).contains(&digits.len()) || !digits.bytes().all(|b| b.is_ascii_digit()) {
                return Err(INVALID);
            }
            let pni = Pni::from_uuid_bytes(exact(m.pni_binary.as_deref())?);
            let keys = identity(
                m.pni_identity_key_public.as_deref(),
                m.pni_identity_key_private.as_deref(),
            )?;
            Some((number.clone(), pni, keys))
        }
        None => None,
    };
    let auth_credential_salt = match &phone {
        Some(_) => None,
        None => Some(exact::<16>(m.auth_credential_salt.as_deref())?.to_vec()),
    };
    let account_entropy_pool = m.account_entropy_pool.ok_or(INVALID)?;
    if account_entropy_pool.len() != 64
        || !account_entropy_pool
            .bytes()
            .all(|b| b.is_ascii_digit() || b.is_ascii_lowercase())
    {
        return Err(INVALID);
    }
    Ok(Provisioned {
        aci: Aci::from_uuid_bytes(exact(m.aci_binary.as_deref())?),
        aci_identity: identity(
            m.aci_identity_key_public.as_deref(),
            m.aci_identity_key_private.as_deref(),
        )?,
        phone,
        auth_credential_salt,
        profile_key: exact(m.profile_key.as_deref())?,
        account_entropy_pool,
        media_root_backup_key: exact(m.media_root_backup_key.as_deref())?,
        read_receipts: m.read_receipts.unwrap_or(false),
        code: m.provisioning_code.filter(|c| !c.is_empty()).ok_or(INVALID)?,
    })
}

/// Encrypts the device name to the account's identity key (`DeviceName` proto).
pub fn encrypt_device_name(name: &str, identity: &IdentityKey) -> Vec<u8> {
    let ephemeral = KeyPair::generate(&mut OsRng.unwrap_err());
    let master = ephemeral
        .calculate_agreement(identity.public_key())
        .expect("same key type");
    let synthetic_iv = hmac(&hmac(&master, b"auth"), name.as_bytes())[..16].to_vec();
    let cipher_key = hmac(&hmac(&master, b"cipher"), &synthetic_iv);
    let mut ciphertext = name.as_bytes().to_vec();
    Aes256Ctr32::from_key(&cipher_key, &[0; 12], 0)
        .expect("valid key")
        .process(&mut ciphertext);
    DeviceName {
        ephemeral_public: Some(ephemeral.public_key.serialize().into_vec()),
        synthetic_iv: Some(synthetic_iv),
        ciphertext: Some(ciphertext),
    }
    .encode_to_vec()
}

/// The keys a new device uploads when it links, for one identity (ACI or PNI).
pub struct LinkKeys {
    pub registration_id: u32,
    pub signed: SignedPreKeyRecord,
    pub last_resort: KyberPreKeyRecord,
}

impl LinkKeys {
    pub fn generate(identity: &IdentityKeyPair) -> Self {
        let mut rng = OsRng.unwrap_err();
        let now = Timestamp::from_epoch_millis(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("after 1970")
                .as_millis() as u64,
        );
        let key_pair = KeyPair::generate(&mut rng);
        let signature = identity
            .private_key()
            .calculate_signature(&key_pair.public_key.serialize(), &mut rng)
            .expect("can sign");
        Self {
            registration_id: rng.random_range(1..=0x3fff),
            signed: SignedPreKeyRecord::new(rng.random_range(1..0xff_ffffu32).into(), now, &key_pair, &signature),
            last_resort: KyberPreKeyRecord::generate(
                kem::KeyType::Kyber1024,
                rng.random_range(1..0xff_ffffu32).into(),
                identity.private_key(),
            )
            .expect("can sign"),
        }
    }

    fn json(&self) -> (Value, Value) {
        fn key<R: GenericSignedPreKey>(record: &R, public: Box<[u8]>) -> Value {
            let id: u32 = record.id().expect("just built").into();
            json!({
                "keyId": id,
                "publicKey": STANDARD_NO_PAD.encode(public),
                "signature": STANDARD_NO_PAD.encode(record.signature().expect("just built")),
            })
        }
        (
            key(&self.signed, self.signed.public_key().expect("just built").serialize()),
            key(
                &self.last_resort,
                self.last_resort.public_key().expect("just built").serialize(),
            ),
        )
    }
}

/// Body of `PUT /v1/devices/link`.
pub fn link_request(code: &str, encrypted_name: &[u8], aci: &LinkKeys, pni: Option<&LinkKeys>) -> Value {
    let (aci_signed, aci_kyber) = aci.json();
    let mut body = json!({
        "verificationCode": code,
        "accountAttributes": {
            // No Apple push: this device keeps its own connection.
            "fetchesMessages": true,
            "registrationId": aci.registration_id,
            "name": STANDARD.encode(encrypted_name),
            "capabilities": {
                "transfer": true,
                "storage": false,
                "spqr": true,
                "attachmentBackfill": true,
                "usernameChangeSyncMessage": true,
                "optionalPhoneNumber": true,
            },
        },
        "aciSignedPreKey": aci_signed,
        "aciPqLastResortPreKey": aci_kyber,
    });
    if let Some(pni) = pni {
        let (signed, kyber) = pni.json();
        body["accountAttributes"]["pniRegistrationId"] = pni.registration_id.into();
        body["pniSignedPreKey"] = signed;
        body["pniPqLastResortPreKey"] = kyber;
    }
    body
}

#[cfg(test)]
pub(crate) mod tests {
    use signal_crypto::aes_256_cbc_encrypt;

    use super::*;

    pub(crate) struct Primary {
        pub aci: IdentityKeyPair,
        pub pni: IdentityKeyPair,
    }

    /// What a primary device does: the encrypt side of ProvisioningCipher.
    pub(crate) fn envelope(to: &PublicKey, edit: impl FnOnce(&mut ProvisionMessage)) -> (Primary, Vec<u8>) {
        let mut rng = OsRng.unwrap_err();
        let primary = Primary {
            aci: IdentityKeyPair::generate(&mut rng),
            pni: IdentityKeyPair::generate(&mut rng),
        };
        let mut message = ProvisionMessage {
            aci_identity_key_public: Some(primary.aci.public_key().serialize().into_vec()),
            aci_identity_key_private: Some(primary.aci.private_key().serialize()),
            pni_identity_key_public: Some(primary.pni.public_key().serialize().into_vec()),
            pni_identity_key_private: Some(primary.pni.private_key().serialize()),
            number: Some("+4915112345678".into()),
            provisioning_code: Some("123456".into()),
            profile_key: Some(vec![3; 32]),
            read_receipts: Some(true),
            account_entropy_pool: Some("a1".repeat(32)),
            media_root_backup_key: Some(vec![4; 32]),
            aci_binary: Some(vec![5; 16]),
            pni_binary: Some(vec![6; 16]),
            ..Default::default()
        };
        edit(&mut message);

        let ephemeral = KeyPair::generate(&mut rng);
        let keys = cipher_and_mac_key(&ephemeral.private_key, to).unwrap();
        let iv = [9u8; 16];
        let mut body = vec![1u8];
        body.extend_from_slice(&iv);
        body.extend(aes_256_cbc_encrypt(&message.encode_to_vec(), &keys[..32], &iv).unwrap());
        let mac = hmac(&keys[32..], &body);
        body.extend(mac);
        let envelope = ProvisionEnvelope {
            public_key: Some(ephemeral.public_key.serialize().into_vec()),
            body: Some(body),
        };
        (primary, envelope.encode_to_vec())
    }

    #[test]
    fn decrypts_and_validates_envelope() {
        let ours = KeyPair::generate(&mut OsRng.unwrap_err());
        let (primary, bytes) = envelope(&ours.public_key, |_| {});
        let p = decrypt_envelope(&ours.private_key, &bytes).unwrap();
        assert_eq!(p.aci_identity.public_key(), primary.aci.public_key());
        assert_eq!(p.phone.as_ref().unwrap().0, "+4915112345678");
        assert_eq!(p.code, "123456");
        assert!(p.read_receipts);

        // A flipped bit anywhere in the body fails the MAC.
        let mut env = ProvisionEnvelope::decode(bytes.as_slice()).unwrap();
        env.body.as_mut().unwrap()[20] ^= 1;
        assert!(decrypt_envelope(&ours.private_key, &env.encode_to_vec()).is_err());
        // Wrong recipient.
        let other = KeyPair::generate(&mut OsRng.unwrap_err());
        assert!(decrypt_envelope(&other.private_key, &bytes).is_err());
        assert!(decrypt_envelope(&ours.private_key, b"junk").is_err());
    }

    #[test]
    fn rejects_incomplete_or_inconsistent_messages() {
        let ours = KeyPair::generate(&mut OsRng.unwrap_err());
        let bad: [fn(&mut ProvisionMessage); 6] = [
            |m| m.profile_key = Some(vec![3; 31]),
            |m| m.provisioning_code = None,
            |m| m.account_entropy_pool = Some("short".into()),
            |m| m.pni_binary = None,
            |m| m.number = Some("4915112345678".into()),
            // Private key that does not belong to the public key.
            |m| m.aci_identity_key_private = m.pni_identity_key_private.clone(),
        ];
        for edit in bad {
            let (_, bytes) = envelope(&ours.public_key, edit);
            assert!(decrypt_envelope(&ours.private_key, &bytes).is_err());
        }
        // No phone number is fine when the salt is there.
        let (_, bytes) = envelope(&ours.public_key, |m| {
            m.number = None;
            m.auth_credential_salt = Some(vec![1; 16]);
        });
        assert!(decrypt_envelope(&ours.private_key, &bytes).unwrap().phone.is_none());
    }

    #[test]
    fn link_url_escapes_base64() {
        let key = PublicKey::deserialize(&[&[5u8][..], &[0xfb; 32]].concat()).unwrap();
        let url = link_url("abc", &key);
        assert!(url.starts_with("sgnl://linkdevice?uuid=abc&pub_key=Bfv7"));
        let value = url.split("pub_key=").nth(1).unwrap().split('&').next().unwrap();
        assert!(!value.contains(['+', '/', '=']), "{value}");
    }

    #[test]
    fn device_name_decrypts_with_identity_key() {
        let identity = IdentityKeyPair::generate(&mut OsRng.unwrap_err());
        let name = DeviceName::decode(encrypt_device_name("Kiri's Mac", identity.identity_key()).as_slice()).unwrap();
        // The receiving side, as in OWSDeviceNames.decryptDeviceName.
        let ephemeral = PublicKey::deserialize(&name.ephemeral_public.unwrap()).unwrap();
        let master = identity.private_key().calculate_agreement(&ephemeral).unwrap();
        let iv = name.synthetic_iv.unwrap();
        let mut text = name.ciphertext.unwrap();
        Aes256Ctr32::from_key(&hmac(&hmac(&master, b"cipher"), &iv), &[0; 12], 0)
            .unwrap()
            .process(&mut text);
        assert_eq!(text, b"Kiri's Mac");
        assert_eq!(hmac(&hmac(&master, b"auth"), &text)[..16], iv[..]);
    }

    #[test]
    fn link_request_has_verifiable_keys() {
        let mut rng = OsRng.unwrap_err();
        let (aci_id, pni_id) = (IdentityKeyPair::generate(&mut rng), IdentityKeyPair::generate(&mut rng));
        let (aci, pni) = (LinkKeys::generate(&aci_id), LinkKeys::generate(&pni_id));
        let body = link_request("123456", b"name", &aci, Some(&pni));
        for (identity, signed, kyber) in [
            (&aci_id, "aciSignedPreKey", "aciPqLastResortPreKey"),
            (&pni_id, "pniSignedPreKey", "pniPqLastResortPreKey"),
        ] {
            for field in [signed, kyber] {
                let get = |k: &str| STANDARD_NO_PAD.decode(body[field][k].as_str().unwrap()).unwrap();
                assert!(
                    identity
                        .public_key()
                        .verify_signature(&get("publicKey"), &get("signature")),
                    "{field}"
                );
            }
        }
        assert_eq!(body["accountAttributes"]["fetchesMessages"], true);
        assert!((1..=0x3fff).contains(&body["accountAttributes"]["pniRegistrationId"].as_u64().unwrap()));
        assert!(link_request("1", b"n", &aci, None).get("pniSignedPreKey").is_none());
    }
}
