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
    private var linking: Task<Void, Never>?

    func start() {
        do {
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let legacy = group.appendingPathComponent("grdb/signal.sqlite")
            if FileManager.default.fileExists(atPath: legacy.path), let key = try Keychain.read(Keychain.legacy) {
                let summary = try legacySummary(databasePath: legacy.path, keySpec: key)
                if summary.hasAccount {
                    screen = .existingData(summary)
                    return
                }
            }

            // Not `grdb…`: the Swift app deletes folders with that prefix.
            let folder = group.appendingPathComponent("ivy-core", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
            self.core = core
            if let account = try core.account() {
                screen = .linked(account)
            } else {
                screen = .link
                startLinking()
            }
        } catch {
            screen = .failed(error.localizedDescription)
        }
    }

    func startLinking() {
        guard let core else { return }
        linking?.cancel()
        link = .connecting
        let name = Host.current().localizedName ?? "Mac"
        linking = Task {
            do {
                let account = try await core.link(deviceName: name, listener: Listener(model: self))
                screen = .linked(account)
            } catch is CancellationError {
            } catch {
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
            .failed(title: localized("ERROR_NETWORK_FAILURE"), message: localized("CORE_LINK_NETWORK_MESSAGE"))
        default:
            .failed(title: localized("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN"), message: localized("CORE_LINK_FAILED_MESSAGE"))
        }
    }

    private static let appGroup = Bundle.main.object(forInfoDictionaryKey: "IvyAppGroup") as? String ?? ""

    private final class Listener: LinkListener, @unchecked Sendable {
        weak var model: AppModel?
        init(model: AppModel) { self.model = model }

        func linkState(state: LinkState) {
            Task { @MainActor [model] in
                switch state {
                case .showCode(let code, _): model?.link = .code(code)
                case .registering: model?.link = .registering
                }
            }
        }
    }
}
