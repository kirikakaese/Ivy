//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

/// Hands Ivy's Apple push token to the push relay. iOS gives the token to the
/// app delegate, which passes it here instead of registering it with Signal.
final class IvyPushToken {

    static let shared = IvyPushToken()

    private let waiting = AtomicValue<[CheckedContinuation<Data?, Never>]>([], lock: .init())

    /// Asks iOS for the push token again when a relay is connected, so a
    /// changed token reaches the relay. Otherwise connects to the built-in
    /// relay, unless the user turned instant notifications off.
    @MainActor
    func refresh() {
        let relay = IvyPushRelay.shared
        if relay.isConnected {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        Task {
            guard
                let relayURL = await relay.relayForAutomaticConnection(),
                let token = await requestToken()
            else {
                return
            }
            do {
                try await relay.connect(relayURL: relayURL, apnsToken: token)
                Logger.info("Connected to the built-in push relay.")
            } catch {
                Logger.warn("Couldn't connect to the built-in push relay: \(error)")
            }
        }
    }

    /// The push token, or `nil` if iOS doesn't hand one out in time.
    @MainActor
    func requestToken() async -> Data? {
        await withCheckedContinuation { continuation in
            waiting.update { $0.append(continuation) }
            UIApplication.shared.registerForRemoteNotifications()
            Task {
                try? await Task.sleep(nanoseconds: 20 * NSEC_PER_SEC)
                self.finish(with: nil)
            }
        }
    }

    func didReceive(_ token: Data) {
        IvyPushRelay.shared.didReceive(apnsToken: token)
        finish(with: token)
    }

    func didFail(_ error: Error) {
        Logger.warn("No push token: \(error)")
        finish(with: nil)
    }

    private func finish(with token: Data?) {
        waiting.swap([]).forEach { $0.resume(returning: token) }
    }
}

/// Settings > Notifications > Push Relay.
final class IvyPushRelayViewController: OWSTableViewController2 {

    static let setupGuideURL = URL(string: "https://github.com/kirikakaese/Ivy/blob/main/docs/PUSH_RELAY.md")!

    private enum DeviceState {
        case checking
        case linked
        case removed
        case unknown
    }

    private var deviceState: DeviceState = .checking

    static var statusText: String {
        IvyPushRelay.shared.isConnected
            ? IvyLocalizedString("PUSH_RELAY_STATUS_ON", comment: "Accessory text when the push relay is set up.")
            : IvyLocalizedString("PUSH_RELAY_STATUS_OFF", comment: "Accessory text when no push relay is set up.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
        checkDevice()
    }

    private func checkDevice() {
        guard IvyPushRelay.shared.isConnected else {
            return
        }
        deviceState = .checking
        Task {
            let linked = await IvyPushRelay.shared.isDeviceLinked()
            deviceState = switch linked {
            case true?: .linked
            case false?: .removed
            case nil: .unknown
            }
            updateTableContents()
        }
    }

    private func updateTableContents() {
        let relay = IvyPushRelay.shared
        let builtInRelay = IvyPushRelay.builtInRelayURL
        let connection = relay.connection

        let contents = OWSTableContents(title: IvyLocalizedString(
            "PUSH_RELAY_TITLE",
            comment: "Title of the push relay settings and the item that opens them.",
        ))

        let introSection = OWSTableSection()
        introSection.footerTitle = IvyLocalizedString(
            "PUSH_RELAY_INTRO",
            comment: "Explains the push relay on its settings screen.",
        )
        if let builtInRelay {
            introSection.add(.switch(
                withText: IvyLocalizedString("PUSH_RELAY_SWITCH", comment: "Switch that turns the push relay on or off."),
                isOn: { connection != nil },
                actionBlock: { [weak self] uiSwitch in
                    if uiSwitch.isOn {
                        self?.connect(to: connection?.relayURL ?? builtInRelay)
                    } else {
                        self?.disconnect(optOut: true)
                    }
                },
            ))
        }
        contents.add(introSection)

        if let connection {
            let statusSection = OWSTableSection()
            statusSection.add(.copyableItem(
                label: IvyLocalizedString("PUSH_RELAY_ADDRESS", comment: "Label for the address of the connected push relay."),
                value: connection.relayURL.host ?? connection.relayURL.absoluteString,
            ))
            statusSection.add(.item(
                name: IvyLocalizedString("PUSH_RELAY_STATE", comment: "Label for the state of the push relay's linked device."),
                accessoryText: stateText,
            ))
            statusSection.add(.disclosureItem(
                withText: IvyLocalizedString("PUSH_RELAY_SERVICE_STATUS", comment: "Item that opens the push relay's public status page."),
                actionBlock: { [weak self] in
                    self?.present(SFSafariViewController(url: IvyPushRelay.statusPageURL(for: connection.relayURL)), animated: true)
                },
            ))
            if deviceState == .removed {
                statusSection.footerTitle = IvyLocalizedString(
                    "PUSH_RELAY_DEVICE_REMOVED_FOOTER",
                    comment: "Shown when the push relay's linked device was removed from the account.",
                )
                statusSection.add(.actionItem(
                    withText: IvyLocalizedString("PUSH_RELAY_RECONNECT", comment: "Button that sets up the push relay again."),
                    actionBlock: { [weak self] in
                        self?.connect(to: connection.relayURL)
                    },
                ))
            }
            if builtInRelay == nil {
                statusSection.add(.actionItem(
                    withText: IvyLocalizedString("PUSH_RELAY_DISCONNECT", comment: "Button that removes the push relay."),
                    textColor: .Signal.red,
                    actionBlock: { [weak self] in
                        self?.confirmDisconnect()
                    },
                ))
            }
            contents.add(statusSection)
        }

        // Any relay can be entered by hand, for example one's own.
        let ownRelaySection = OWSTableSection()
        ownRelaySection.headerTitle = builtInRelay == nil ? nil : IvyLocalizedString(
            "PUSH_RELAY_OWN_HEADER",
            comment: "Header of the section for using one's own push relay instead of the built-in one.",
        )
        ownRelaySection.footerTitle = IvyLocalizedString(
            "PUSH_RELAY_ACCOUNT_ID_FOOTER",
            comment: "Explains that a relay can be limited to the account ID.",
        )
        ownRelaySection.add(.disclosureItem(
            withText: IvyLocalizedString("PUSH_RELAY_SETUP_GUIDE", comment: "Item that opens the guide for setting up a push relay."),
            actionBlock: { [weak self] in
                self?.present(SFSafariViewController(url: Self.setupGuideURL), animated: true)
            },
        ))
        if let accountId = relay.accountId {
            ownRelaySection.add(.copyableItem(
                label: IvyLocalizedString("PUSH_RELAY_ACCOUNT_ID", comment: "Label for the account ID a push relay can be limited to."),
                value: accountId,
            ))
        }
        ownRelaySection.add(.actionItem(
            withText: builtInRelay == nil && connection == nil
                ? IvyLocalizedString("PUSH_RELAY_CONNECT", comment: "Button that connects Ivy to a push relay.")
                : IvyLocalizedString("PUSH_RELAY_USE_OTHER", comment: "Button that connects Ivy to a push relay other than the current one."),
            actionBlock: { [weak self] in
                self?.askForAddress()
            },
        ))
        contents.add(ownRelaySection)

        self.contents = contents
    }

    private var stateText: String {
        switch deviceState {
        case .checking, .unknown:
            return IvyLocalizedString("PUSH_RELAY_STATE_UNKNOWN", comment: "The push relay's linked device couldn't be checked.")
        case .linked:
            return IvyLocalizedString("PUSH_RELAY_STATE_CONNECTED", comment: "The push relay is set up and its linked device exists.")
        case .removed:
            return IvyLocalizedString("PUSH_RELAY_STATE_REMOVED", comment: "The push relay's linked device was removed.")
        }
    }

    // MARK: - Connecting

    private func askForAddress() {
        let alert = UIAlertController(
            title: IvyLocalizedString("PUSH_RELAY_CONNECT", comment: "Button that connects Ivy to a push relay."),
            message: IvyLocalizedString("PUSH_RELAY_ADDRESS_PROMPT", comment: "Asks for the address of the push relay."),
            preferredStyle: .alert,
        )
        alert.addTextField { field in
            field.placeholder = "relay.example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .URL
        }
        alert.addAction(UIAlertAction(title: CommonStrings.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: CommonStrings.continueButton, style: .default) { [weak self, weak alert] _ in
            guard let url = IvyPushRelay.relayURL(from: alert?.textFields?.first?.text ?? "") else {
                self?.showError(IvyPushRelay.RelayError.invalidAddress)
                return
            }
            self?.connect(to: url)
        })
        present(alert, animated: true)
    }

    private func connect(to relayURL: URL) {
        Task {
            do {
                try await ModalActivityIndicatorViewController.presentAndPropagateResult(from: self) {
                    guard let token = await IvyPushToken.shared.requestToken() else {
                        throw PushTokenUnavailable()
                    }
                    try await IvyPushRelay.shared.connect(relayURL: relayURL, apnsToken: token)
                }
                deviceState = .linked
                updateTableContents()
                presentToast(text: IvyLocalizedString("PUSH_RELAY_CONNECTED_TOAST", comment: "Shown after Ivy connected to the push relay."))
            } catch {
                Logger.warn("Couldn't connect the push relay: \(error)")
                updateTableContents()
                showError(error)
            }
        }
    }

    private struct PushTokenUnavailable: Error {}

    private func showError(_ error: Error) {
        let message: String
        switch error {
        case is PushTokenUnavailable:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_TOKEN", comment: "Shown when iOS gave Ivy no push token.")
        case IvyPushRelay.RelayError.invalidAddress:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_ADDRESS", comment: "Shown when the push relay address is not a valid HTTPS address.")
        case IvyPushRelay.RelayError.notARelay:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_NOT_A_RELAY", comment: "Shown when no push relay answers at the address.")
        case IvyPushRelay.RelayError.accountNotAllowed:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_ACCOUNT", comment: "Shown when the push relay doesn't allow this account.")
        case IvyPushRelay.RelayError.endpointNotAllowed:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_GATEWAY", comment: "Shown when the push relay may not call its push gateway.")
        case IvyPushRelay.RelayError.tooManyDevices:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_DEVICES", comment: "Shown when the account has the most linked devices allowed.")
        case IvyPushRelay.RelayError.notPrimaryDevice:
            message = IvyLocalizedString("PUSH_RELAY_ERROR_PRIMARY", comment: "Shown when the push relay is set up on a linked device.")
        default:
            message = String(
                format: IvyLocalizedString("PUSH_RELAY_ERROR_DETAILS_FORMAT", comment: "Error message when connecting to the push relay failed for another reason. Embeds {{ the general message }} and {{ technical details for a bug report }}."),
                IvyLocalizedString("PUSH_RELAY_ERROR_GENERIC", comment: "Shown when connecting to the push relay failed for another reason."),
                String(String(describing: error).prefix(400)),
            )
        }
        OWSActionSheets.showActionSheet(
            title: IvyLocalizedString("PUSH_RELAY_ERROR_TITLE", comment: "Title shown when connecting to the push relay failed."),
            message: message,
            fromViewController: self,
        )
    }

    // MARK: - Disconnecting

    private func confirmDisconnect() {
        OWSActionSheets.showConfirmationAlert(
            title: IvyLocalizedString("PUSH_RELAY_DISCONNECT_TITLE", comment: "Title of the confirmation before removing the push relay."),
            message: IvyLocalizedString("PUSH_RELAY_DISCONNECT_MESSAGE", comment: "Explains what removing the push relay does."),
            proceedTitle: IvyLocalizedString("PUSH_RELAY_DISCONNECT", comment: "Button that removes the push relay."),
            proceedStyle: .destructive,
            proceedAction: { [weak self] _ in
                self?.disconnect(optOut: false)
            },
            fromViewController: self,
        )
    }

    private func disconnect(optOut: Bool) {
        Task {
            do {
                try await ModalActivityIndicatorViewController.presentAndPropagateResult(from: self) {
                    try await IvyPushRelay.shared.disconnect(optOut: optOut)
                }
                UIApplication.shared.unregisterForRemoteNotifications()
                updateTableContents()
            } catch {
                updateTableContents()
                Logger.warn("Couldn't remove the push relay: \(error)")
                OWSActionSheets.showActionSheet(
                    title: IvyLocalizedString("PUSH_RELAY_DISCONNECT_ERROR", comment: "Shown when the push relay's linked device couldn't be removed."),
                    fromViewController: self,
                )
            }
        }
    }
}
