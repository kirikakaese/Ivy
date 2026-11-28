//! Linking this installation to an account as a secondary device, end to end.

use std::time::Duration;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use http::{HeaderMap, HeaderValue, Method, StatusCode, header};
use libsignal_net::chat::server_requests::ProvisioningEvent;
use libsignal_net::chat::{LanguageList, Request, UnauthenticatedChatHeaders};
use libsignal_net::env::constants::{CHAT_PROVISIONING_PATH, CHAT_WEBSOCKET_PATH};
use libsignal_protocol::KeyPair;
use rand::{RngCore as _, TryRngCore as _, rngs::OsRng};
use serde::Deserialize;
use tokio::sync::mpsc;

use crate::CoreError;
use crate::account::Account;
use crate::net::Net;
use crate::provisioning::{LinkKeys, Provisioned, decrypt_envelope, encrypt_device_name, link_request, link_url};

pub struct Linked {
    pub account: Account,
    pub aci_keys: LinkKeys,
    pub pni_keys: Option<LinkKeys>,
}

/// Waits on the provisioning socket until the primary device sends its message.
/// `show_url` gets a new URL whenever the server hands out a new address.
async fn await_primary(net: &Net, show_url: &(dyn Fn(String) + Send + Sync)) -> Result<Provisioned, CoreError> {
    let ours = KeyPair::generate(&mut OsRng.unwrap_err());
    loop {
        let (events, mut inbox) = mpsc::unbounded_channel();
        let _connection = net
            .connect(
                CHAT_PROVISIONING_PATH,
                None,
                Box::new(move |event| match ProvisioningEvent::try_from(event) {
                    Ok(event) => drop(events.send(event)),
                    // libsignal reports (usually empty) alerts on every connection; provisioning has no use for them.
                    Err(e) => log::debug!("ignoring provisioning event: {e}"),
                }),
            )
            .await?;
        loop {
            match inbox.recv().await {
                Some(ProvisioningEvent::ReceivedAddress { address, send_ack }) => {
                    let _ = send_ack(StatusCode::OK);
                    show_url(link_url(&address, &ours.public_key));
                }
                Some(ProvisioningEvent::ReceivedEnvelope { envelope, send_ack }) => {
                    let _ = send_ack(StatusCode::OK);
                    return decrypt_envelope(&ours.private_key, &envelope);
                }
                Some(ProvisioningEvent::ServerTimestamp(_)) => {}
                // The server closes idle provisioning sockets; start over with a new address.
                Some(ProvisioningEvent::Stopped(_)) | None => break,
            }
        }
        // Never reconnect in a tight loop if the server keeps closing the socket.
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LinkResponse {
    device_id: u32,
}

fn linked(
    p: Provisioned,
    password: String,
    response: &[u8],
    aci_keys: LinkKeys,
    pni_keys: Option<LinkKeys>,
) -> Result<Linked, CoreError> {
    let response: LinkResponse = serde_json::from_slice(response).map_err(|e| CoreError::Network(e.to_string()))?;
    // 1 is the primary; the server never assigns it to a linked device.
    if !(2..=127).contains(&response.device_id) {
        return Err(CoreError::Network("device id out of range".into()));
    }
    let (number, pni, pni_identity) = match p.phone {
        Some((number, pni, keys)) => (
            Some(number),
            Some(pni.service_id_string()),
            Some(keys.serialize().into_vec()),
        ),
        None => (None, None, None),
    };
    Ok(Linked {
        account: Account {
            aci: p.aci.service_id_string(),
            device_id: response.device_id,
            password,
            aci_identity: p.aci_identity.serialize().into_vec(),
            aci_registration_id: aci_keys.registration_id,
            number,
            pni,
            pni_identity,
            pni_registration_id: pni_keys.as_ref().map(|k| k.registration_id),
            auth_credential_salt: p.auth_credential_salt,
            profile_key: p.profile_key.to_vec(),
            account_entropy_pool: p.account_entropy_pool,
            media_root_backup_key: p.media_root_backup_key.to_vec(),
            read_receipts: p.read_receipts,
        },
        aci_keys,
        pni_keys,
    })
}

/// Registers this device with the server, with the code from the primary.
async fn register(net: &Net, p: Provisioned, device_name: &str) -> Result<Linked, CoreError> {
    let aci_keys = LinkKeys::generate(&p.aci_identity);
    let pni_keys = p.phone.as_ref().map(|(_, _, identity)| LinkKeys::generate(identity));
    let name = encrypt_device_name(device_name, p.aci_identity.identity_key());
    let body = link_request(&p.code, &name, &aci_keys, pni_keys.as_ref());

    let mut password = [0u8; 18];
    OsRng.unwrap_err().fill_bytes(&mut password);
    let password = STANDARD.encode(password);
    let auth = STANDARD.encode(format!("{}:{password}", p.aci.service_id_string()));
    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/json"));
    headers.insert(
        header::AUTHORIZATION,
        format!("Basic {auth}").parse().expect("base64 is a valid header"),
    );

    let chat = net
        .connect(
            CHAT_WEBSOCKET_PATH,
            Some(
                UnauthenticatedChatHeaders {
                    languages: LanguageList::default(),
                }
                .into(),
            ),
            Box::new(|_| {}),
        )
        .await?;
    let request = Request {
        method: Method::PUT,
        path: "/v1/devices/link".parse().expect("valid path"),
        headers,
        body: Some(serde_json::to_vec(&body).expect("plain data").into()),
    };
    let response = chat
        .send(request, Duration::from_secs(30))
        .await
        .map_err(|e| CoreError::Network(e.to_string()))?;
    chat.disconnect().await;
    match response.status.as_u16() {
        200 => linked(
            p,
            password,
            response.body.as_deref().unwrap_or_default(),
            aci_keys,
            pni_keys,
        ),
        409 => Err(CoreError::Obsolete),
        411 => Err(CoreError::DeviceLimit),
        status => Err(CoreError::LinkRefused(status)),
    }
}

pub async fn link(
    net: &Net,
    device_name: &str,
    show_url: &(dyn Fn(String) + Send + Sync),
    registering: &(dyn Fn() + Send + Sync),
) -> Result<Linked, CoreError> {
    let provisioned = await_primary(net, show_url).await?;
    registering();
    register(net, provisioned, device_name).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{account, db, provisioning};

    #[test]
    fn linked_account_is_stored_with_its_prekeys() {
        let ours = KeyPair::generate(&mut OsRng.unwrap_err());
        let (primary, envelope) = provisioning::tests::envelope(&ours.public_key, |_| {});
        let p = decrypt_envelope(&ours.private_key, &envelope).unwrap();
        let (aci_keys, pni_keys) = (LinkKeys::generate(&primary.aci), LinkKeys::generate(&primary.pni));

        let ok = br#"{"uuid":"x","pni":"y","deviceId":2}"#;
        let l = linked(p, "pw".into(), ok, aci_keys, Some(pni_keys)).unwrap();
        assert_eq!(l.account.device_id, 2);
        assert_eq!(l.account.number.as_deref(), Some("+4915112345678"));
        assert_eq!(l.account.aci_identity, primary.aci.serialize().into_vec());

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("core.sqlite");
        let key = [5u8; db::KEY_SPEC_LEN];
        let mut conn = db::open_core(&path, &key).unwrap();
        assert_eq!(account::load(&conn).unwrap(), None);
        account::save(&mut conn, &l.account, &l.aci_keys, l.pni_keys.as_ref()).unwrap();
        drop(conn);
        let conn = db::open_core(&path, &key).unwrap();
        assert_eq!(account::load(&conn).unwrap(), Some(l.account));
        // Signed and last-resort Kyber prekey for ACI and PNI.
        assert_eq!(
            conn.query_row("SELECT count(*) FROM prekey", [], |r| r.get::<_, u32>(0))
                .unwrap(),
            4
        );
    }

    #[test]
    fn rejects_bad_link_responses() {
        let ours = KeyPair::generate(&mut OsRng.unwrap_err());
        for response in [&br#"{"deviceId":1}"#[..], br#"{"deviceId":4000}"#, b"{}", b""] {
            let (primary, envelope) = provisioning::tests::envelope(&ours.public_key, |_| {});
            let p = decrypt_envelope(&ours.private_key, &envelope).unwrap();
            assert!(linked(p, "pw".into(), response, LinkKeys::generate(&primary.aci), None).is_err());
        }
    }

    /// Talks to Signal's production server: `cargo test -- --ignored live`. Creates nothing there;
    /// a provisioning address is anonymous and expires by itself.
    #[tokio::test]
    #[ignore = "needs a direct network path to chat.signal.org"]
    async fn live_provisioning_socket_hands_out_a_link() {
        let net = Net::new("iOS/18.5");
        let (tx, mut rx) = mpsc::unbounded_channel();
        let show = move |url: String| drop(tx.send(url));
        let url = tokio::select! {
            r = await_primary(&net, &show) => panic!("ended early: {:?}", r.err()),
            url = rx.recv() => url.unwrap(),
            _ = tokio::time::sleep(Duration::from_secs(30)) => panic!("no address in 30 s"),
        };
        assert!(url.starts_with("sgnl://linkdevice?uuid="), "{url}");
    }
}
