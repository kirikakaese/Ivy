import Foundation
import SwiftUI

/// Bridges the core to SwiftUI: holds what the core reports, decides nothing.
@MainActor
final class AppModel: ObservableObject {
    enum Screen {
        case starting
        case failed(String)
        /// The Swift app's data is on this Mac; this version cannot take it over yet and must not link beside it.
        case existingData(LegacySummary)
        case link
        case linked(AccountSummary)
    }

    enum Link {
        case connecting
        case code(QrCode)
        case registering
        case failed(title: String, message: String)
    }

    @Published var screen: Screen = .starting
    @Published var link: Link = .connecting

    private var core: Core?
    /// The running link attempt; callbacks from any other attempt are ignored.
    private var attempt: Int?
    private var attempts = 0

    func start() {
        // The window's task runs again each time the window reopens.
        guard case .starting = screen else { return }
        Task.detached {
            let (core, screen) = Self.open()
            await MainActor.run {
                self.core = core
                self.screen = screen
                if case .link = screen { self.startLinking() }
            }
        }
    }

    /// Off the main thread: Keychain, database open and the old database's counts can take a while.
    private nonisolated static func open() -> (Core?, Screen) {
        let files = FileManager.default
        let appGroup = Bundle.main.object(forInfoDictionaryKey: "IvyAppGroup") as? String ?? ""
        guard let group = files.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return (nil, .failed(IvyLocalizedString("CORE_NO_APP_GROUP_MESSAGE")))
        }

        // Any trace of the Swift app's database stops here, so this Mac never links beside data it should take over.
        let legacy = group.appendingPathComponent("grdb/signal.sqlite")
        if files.fileExists(atPath: legacy.path) {
            guard
                let key = try? Keychain.read(Keychain.legacy),
                let summary = try? legacySummary(databasePath: legacy.path, keySpec: key)
            else {
                return (nil, .failed(IvyLocalizedString("CORE_EXISTING_DATA_UNREADABLE_MESSAGE")))
            }
            return (nil, .existingData(summary))
        }

        do {
            // Not `grdb…`: the Swift app deletes folders with that prefix.
            let folder = group.appendingPathComponent("ivy-core", isDirectory: true)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let key: Data
            if let stored = try Keychain.read(Keychain.core) {
                key = stored
            } else {
                key = newKeySpec()
                try Keychain.add(key, Keychain.core)
            }
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let core = try Core(
                databasePath: folder.appendingPathComponent("core.sqlite").path,
                keySpec: key,
                osVersion: "macOS/\(version.majorVersion).\(version.minorVersion)"
            )
            if let account = try core.account() {
                return (core, .linked(account))
            }
            return (core, .link)
        } catch {
            return (nil, .failed(error.localizedDescription))
        }
    }

    func startLinking() {
        guard let core, attempt == nil else { return }
        attempts += 1
        let current = attempts
        attempt = current
        link = .connecting
        let name = Host.current().localizedName ?? "Mac"
        let listener = Listener { [weak self] state in
            Task { @MainActor in
                guard let self, self.attempt == current else { return }
                switch state {
                case .showCode(let code): self.link = .code(code)
                case .registering: self.link = .registering
                }
            }
        }
        Task {
            do {
                let account = try await core.link(deviceName: name, listener: listener)
                attempt = nil
                screen = .linked(account)
            } catch {
                attempt = nil
                link = Self.failure(error)
            }
        }
    }

    /// Picks the translated text for a core error.
    private static func failure(_ error: Error) -> Link {
        switch error as? CoreError {
        case .DeviceLimit:
            .failed(title: localized("MULTIDEVICE_PAIRING_MAX_DESC"), message: localized("MULTIDEVICE_PAIRING_MAX_RECOVERY"))
        case .Obsolete:
            .failed(
                title: localized("SECONDARY_LINKING_ERROR_OBSOLETE_LINKED_DEVICE_TITLE"),
                message: localized("SECONDARY_LINKING_ERROR_OBSOLETE_LINKED_DEVICE_MESSAGE"))
        case .Network:
            .failed(title: localized("ERROR_NETWORK_FAILURE"), message: IvyLocalizedString("CORE_LINK_NETWORK_MESSAGE"))
        // During linking the database is only written after Signal accepted the device.
        case .Database:
            .failed(
                title: localized("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN"),
                message: IvyLocalizedString("CORE_LINK_SAVE_FAILED_MESSAGE"))
        default:
            .failed(
                title: localized("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN"),
                message: IvyLocalizedString("CORE_LINK_FAILED_MESSAGE"))
        }
    }

    private final class Listener: LinkListener, @unchecked Sendable {
        let onState: (LinkState) -> Void
        init(_ onState: @escaping (LinkState) -> Void) { self.onState = onState }
        func linkState(state: LinkState) { onState(state) }
    }
}
