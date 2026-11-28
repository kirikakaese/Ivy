//! Names from Signal profiles: fetched with the profile key a contact's messages carry, decrypted here.

use libsignal_core::Aci;
use rusqlite::{Connection, params};
use signal_crypto::Aes256GcmDecryption;
use zkgroup::profiles::ProfileKey;

/// The versioned profile request path, which the server answers only for holders of the profile key.
pub fn path(aci: &str, key: &[u8; 32]) -> Option<String> {
    let aci = Aci::parse_from_service_id_string(aci)?;
    let version = ProfileKey::create(*key).get_profile_key_version(aci);
    Some(format!("/v1/profile/{}/{}", aci.service_id_string(), version.as_ref()))
}

/// Names come from other people: control and direction-override characters could disguise them.
fn clean(part: &[u8]) -> Option<String> {
    let text = std::str::from_utf8(part).ok()?;
    let clean: String = text
        .chars()
        .filter(|c| !c.is_control() && !('\u{202A}'..='\u{202E}').contains(c) && !('\u{2066}'..='\u{2069}').contains(c))
        .collect();
    Some(clean.trim().to_owned()).filter(|s| !s.is_empty())
}

/// The display name in an encrypted profile name (nonce, AES-256-GCM ciphertext, tag), stored as
/// "<given>\0<family>" padded with zeros, as the Swift app reads it.
pub fn decrypt_name(key: &[u8; 32], encrypted: &[u8]) -> Option<String> {
    if encrypted.len() < 12 + 16 {
        return None;
    }
    let (nonce, rest) = encrypted.split_at(12);
    let (ciphertext, tag) = rest.split_at(rest.len() - 16);
    let mut plaintext = ciphertext.to_vec();
    let mut gcm = Aes256GcmDecryption::new(key, nonce, &[]).ok()?;
    gcm.decrypt(&mut plaintext);
    gcm.verify_tag(tag).ok()?;
    let mut parts = plaintext.splitn(3, |&b| b == 0);
    let given = clean(parts.next()?)?;
    // shortcut: "given family" for every language; use the locale's name order with the settings slice.
    Some(match parts.next().and_then(clean) {
        Some(family) => format!("{given} {family}"),
        None => given,
    })
}

/// Contacts whose profile key is known but whose name isn't.
pub fn missing(db: &Connection) -> rusqlite::Result<Vec<(String, [u8; 32])>> {
    let mut query =
        db.prepare("SELECT service_id, profile_key FROM recipient WHERE profile_key IS NOT NULL AND name IS NULL")?;
    let rows = query.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Vec<u8>>(1)?)))?;
    Ok(rows
        .filter_map(Result::ok)
        .filter_map(|(id, key)| Some((id, key.try_into().ok()?)))
        .collect())
}

pub fn save(db: &Connection, aci: &str, name: &str) -> rusqlite::Result<()> {
    db.execute(
        "UPDATE recipient SET name = ?2 WHERE service_id = ?1",
        params![aci, name],
    )
    .map(drop)
}

#[cfg(test)]
mod tests {
    use signal_crypto::Aes256GcmEncryption;

    use super::*;

    fn encrypt(key: &[u8; 32], plaintext: &[u8]) -> Vec<u8> {
        let nonce = [3u8; 12];
        let mut buf = plaintext.to_vec();
        let mut gcm = Aes256GcmEncryption::new(key, &nonce, &[]).unwrap();
        gcm.encrypt(&mut buf);
        [&nonce[..], &buf, &gcm.compute_tag()].concat()
    }

    #[test]
    fn decrypts_padded_names_and_strips_disguises() {
        let key = [9u8; 32];
        let mut padded = b"Ada\0Lovelace".to_vec();
        padded.resize(53, 0);
        assert_eq!(
            decrypt_name(&key, &encrypt(&key, &padded)).as_deref(),
            Some("Ada Lovelace")
        );
        assert_eq!(
            decrypt_name(&key, &encrypt(&key, "Mallory\u{202E}gnp.exe\0".as_bytes())).as_deref(),
            Some("Mallorygnp.exe")
        );
        assert_eq!(decrypt_name(&[8u8; 32], &encrypt(&key, b"Ada")), None, "wrong key");
        assert_eq!(decrypt_name(&key, &encrypt(&key, b"\0Lovelace")), None, "no given name");
    }

    #[test]
    fn versioned_path() {
        let path = path("00000000-0000-4000-8000-0000000000a1", &[1; 32]).unwrap();
        let version = path.rsplit('/').next().unwrap();
        assert!(path.starts_with("/v1/profile/00000000-0000-4000-8000-0000000000a1/"));
        assert_eq!(version.len(), 64);
        assert!(version.bytes().all(|b| b.is_ascii_hexdigit()));
    }
}
