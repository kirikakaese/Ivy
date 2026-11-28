//! Connections to Signal's chat service through libsignal-net (TLS pinning and routing are libsignal's).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use http::HeaderName;
use libsignal_net::chat::{ChatConnection, ChatHeaders, ConnectError, ws};
use libsignal_net::connect_state::{
    ConnectState, ConnectionResources, DefaultConnectorFactory, PreconnectingFactory, SUGGESTED_CONNECT_CONFIG,
};
use libsignal_net::env::{Env, PROD, StaticIpOrder, UserAgent};
use libsignal_net::infra::OverrideNagleAlgorithm;
use libsignal_net::infra::route::DirectOrProxyProvider;
use libsignal_net_infra::EnableDomainFronting;
use libsignal_net_infra::dns::DnsResolver;
use libsignal_net_infra::route::DirectOrProxyMode;
use libsignal_net_infra::utils::no_network_change_events;

use crate::CoreError;

pub struct Net {
    env: Env<'static>,
    connect_state: Mutex<ConnectState<PreconnectingFactory>>,
    dns: DnsResolver,
    user_agent: UserAgent,
}

impl From<ConnectError> for CoreError {
    fn from(e: ConnectError) -> Self {
        match e {
            ConnectError::AppExpired => Self::Obsolete,
            ConnectError::DeviceDeregistered => Self::Unlinked,
            e => Self::Network(e.to_string()),
        }
    }
}

impl Net {
    /// `os_version` as the Swift app reports it, e.g. "iOS/18.5".
    pub fn new(os_version: &str) -> Self {
        // Signal's servers see the upstream release Ivy is built on, like the Swift app (Config/Ivy.xcconfig).
        let user_agent = format!("Signal-iOS/{} {os_version}", env!("IVY_UPSTREAM_VERSION"));
        Self {
            env: PROD,
            connect_state: ConnectState::new_with_transport_connector(
                SUGGESTED_CONNECT_CONFIG,
                PreconnectingFactory::new(DefaultConnectorFactory, Duration::ZERO),
            ),
            dns: DnsResolver::new_with_static_fallback(
                PROD.static_fallback(StaticIpOrder::HARDCODED),
                &no_network_change_events(),
            ),
            user_agent: UserAgent::with_libsignal_version(&user_agent),
        }
    }

    /// Opens a chat websocket on `path`; `listener` gets what the server sends.
    pub async fn connect(
        &self,
        path: &'static str,
        headers: Option<ChatHeaders>,
        listener: ws::EventListener,
    ) -> Result<ChatConnection, CoreError> {
        let chat = &self.env.chat_domain_config.connect;
        // shortcut: direct routes only, no censorship circumvention or user proxy; add with the settings slice.
        let routes = DirectOrProxyProvider {
            inner: chat.route_provider(EnableDomainFronting::No, OverrideNagleAlgorithm::UseSystemDefault),
            mode: DirectOrProxyMode::DirectOnly,
        };
        // shortcut: network changes are not observed yet; the receive slice adds reconnects.
        let network_change_event = no_network_change_events();
        let resources = ConnectionResources {
            connect_state: &self.connect_state,
            dns_resolver: &self.dns,
            network_change_event: &network_change_event,
            confirmation_header_name: chat.confirmation_header_name.map(HeaderName::from_static),
        };
        let pending = ChatConnection::start_connect_with(
            resources,
            chat.service,
            routes,
            path,
            &self.user_agent,
            self.env.chat_ws_config,
            headers,
            "ivy",
        )
        .await?;
        Ok(ChatConnection::finish_connect(
            tokio::runtime::Handle::current(),
            pending,
            HashMap::new(),
            listener,
        ))
    }
}
