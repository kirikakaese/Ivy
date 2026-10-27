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
    /// changed token reaches the relay.
    @MainActor
    func refreshIfConnected() {
        guard IvyPushRelay.shared.isConnected else {
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
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
        let contents = OWSTableContents(title: IvyLocalizedString(
            "PUSH_RELAY_TITLE",
            comment: "Title of the push relay settings and the item that opens them.",
        ))

        let introSection = OWSTableSection()
        introSection.footerTitle = IvyLocalizedString(
            "PUSH_RELAY_INTRO",
            comment: "Explains the push relay on its settings screen.",
        )
        introSection.add(.disclosureItem(
            withText: IvyLocalizedString("PUSH_RELAY_SETUP_GUIDE", comment: "Item that opens the guide for setting up a push relay."),
            actionBlock: { [weak self] in
                self?.present(SFSafariViewController(url: Self.setupGuideURL), animated: true)
            },
        ))
        contents.add(introSection)

        if let connection = IvyPushRelay.shared.connection {
            let statusSection = OWSTableSection()
            statusSection.add(.copyableItem(
                label: IvyLocalizedString("PUSH_RELAY_ADDRESS", comment: "Label for the address of the connected push relay."),
                value: connection.relayURL.host ?? connection.relayURL.absoluteString,
            ))
            statusSection.add(.item(
                name: IvyLocalizedString("PUSH_RELAY_STATE", comment: "Label for the state of the push relay's linked device."),
                accessoryText: stateText,
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
            contents.add(statusSection)

            let disconnectSection = OWSTableSection()
            disconnectSection.add(.actionItem(
                withText: IvyLocalizedString("PUSH_RELAY_DISCONNECT", comment: "Button that removes the push relay."),
                textColor: .Signal.red,
                actionBlock: { [weak self] in
                    self?.confirmDisconnect()
                },
            ))
            contents.add(disconnectSection)
        } else {
            let connectSection = OWSTableSection()
            if let accountId = IvyPushRelay.shared.accountId {
                connectSection.footerTitle = IvyLocalizedString(
                    "PUSH_RELAY_ACCOUNT_ID_FOOTER",
                    comment: "Explains that the relay needs the account ID.",
                )
                connectSection.add(.copyableItem(
                    label: IvyLocalizedString("PUSH_RELAY_ACCOUNT_ID", comment: "Label for the account ID the push relay must allow."),
                    value: accountId,
                ))
            }
            connectSection.add(.actionItem(
                withText: IvyLocalizedString("PUSH_RELAY_CONNECT", comment: "Button that connects Ivy to a push relay."),
                actionBlock: { [weak self] in
                    self?.askForAddress()
                },
            ))
            contents.add(connectSection)
        }

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
            message = IvyLocalizedString("PUSH_RELAY_ERROR_GENERIC", comment: "Shown when connecting to the push relay failed for another reason.")
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
                self?.disconnect()
            },
            fromViewController: self,
        )
    }

    private func disconnect() {
        Task {
            do {
                try await ModalActivityIndicatorViewController.presentAndPropagateResult(from: self) {
                    try await IvyPushRelay.shared.disconnect()
                }
                UIApplication.shared.unregisterForRemoteNotifications()
                updateTableContents()
            } catch {
                Logger.warn("Couldn't remove the push relay: \(error)")
                OWSActionSheets.showActionSheet(
                    title: IvyLocalizedString("PUSH_RELAY_DISCONNECT_ERROR", comment: "Shown when the push relay's linked device couldn't be removed."),
                    fromViewController: self,
                )
            }
        }
    }
}
