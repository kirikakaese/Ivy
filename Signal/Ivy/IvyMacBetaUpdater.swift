//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

#if targetEnvironment(macCatalyst)

import CryptoKit
import SignalServiceKit
import SignalUI

/// Keeps the Mac beta up to date: looks for a newer "Ivy Mac beta" on the
/// releases page when Ivy becomes active (at most every six hours), offers
/// it, and installs it in place: download, check the SHA-256 from the
/// release notes, unpack, swap the app and open the new one. Only in the
/// Mac beta; signed builds will update another way.
@MainActor
enum IvyMacBetaUpdater {

    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let lastCheckKey = "IvyMacBetaLastUpdateCheck"
    private static let skippedKey = "IvyMacBetaSkippedUpdate"
    private static var isBusy = false

    static var isAvailable: Bool {
        #if IVY_MAC_BETA
        return IvyMacBetaRelease.currentNumber != nil
        #else
        return false
        #endif
    }

    static func start() {
        guard isAvailable else {
            return
        }
        NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { checkIfDue() }
        }
        checkIfDue()
    }

    private static func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > checkInterval else {
            return
        }
        Task { await check(userInitiated: false) }
    }

    /// Looks for a newer beta. Asked for by hand, it also says when there is
    /// none, and offers a version skipped before.
    static func check(userInitiated: Bool) async {
        guard isAvailable, !isBusy, let current = IvyMacBetaRelease.currentNumber else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        let newest: IvyMacBetaRelease?
        do {
            var request = URLRequest(url: IvyMacBetaRelease.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            newest = IvyMacBetaRelease.newest(inReleasesJSON: data)
        } catch {
            Logger.warn("Couldn't look for a Mac beta update: \(error)")
            if userInitiated {
                showMessage(IvyLocalizedString("MAC_BETA_UPDATE_CHECK_FAILED", comment: "Shown when Ivy couldn't look for a newer Mac beta."))
            }
            return
        }
        guard let newest, newest.number > current else {
            if userInitiated {
                showMessage(String(
                    format: IvyLocalizedString("MAC_BETA_UP_TO_DATE_FORMAT", comment: "Shown when the Mac beta is the newest one. Embeds {{ beta number }}."),
                    current,
                ))
            }
            return
        }
        if !userInitiated, UserDefaults.standard.integer(forKey: skippedKey) == newest.number {
            return
        }
        offer(newest)
    }

    private static func offer(_ release: IvyMacBetaRelease) {
        guard let presenter = CurrentAppContext().frontmostViewController() else {
            return
        }
        let sheet = ActionSheetController(
            title: String(
                format: IvyLocalizedString("MAC_BETA_UPDATE_TITLE_FORMAT", comment: "Title when a newer Mac beta is out. Embeds {{ beta number }}."),
                release.number,
            ),
            message: IvyLocalizedString("MAC_BETA_UPDATE_MESSAGE", comment: "Explains updating the Mac beta: Ivy restarts, and macOS may ask once to open it."),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("MAC_BETA_UPDATE_NOW", comment: "Button that downloads and installs the newer Mac beta."),
            style: .default,
        ) { _ in
            Task { await install(release) }
        })
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("MAC_BETA_UPDATE_LATER", comment: "Button that skips this Mac beta update until asked again."),
            style: .cancel,
        ) { _ in
            UserDefaults.standard.set(release.number, forKey: skippedKey)
        })
        presenter.presentActionSheet(sheet)
    }

    // MARK: - Installing

    enum UpdateError: Error {
        case checksumMismatch
        case noAppInArchive
        case unpackFailed
    }

    private static func install(_ release: IvyMacBetaRelease) async {
        guard !isBusy, let presenter = CurrentAppContext().frontmostViewController() else {
            return
        }
        isBusy = true
        ModalActivityIndicatorViewController.present(fromViewController: presenter, canCancel: false) { modal in
            defer { isBusy = false }
            do {
                let newApp = try await download(release)
                let installed = try replaceCurrentApp(with: newApp)
                modal.dismiss {
                    relaunch(installed)
                }
            } catch {
                Logger.warn("Couldn't install Mac beta \(release.number): \(error)")
                modal.dismiss {
                    offerManualInstall(release)
                }
            }
        }
    }

    /// Downloads, checks and unpacks the beta; returns the unpacked app.
    private static func download(_ release: IvyMacBetaRelease) async throws -> URL {
        let (file, _) = try await URLSession.shared.download(from: release.zipURL)
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else {
            throw UpdateError.checksumMismatch
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("IvyBetaUpdate-\(release.number)", isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(IvyMacBetaRelease.assetName)
        try FileManager.default.moveItem(at: file, to: zip)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else {
            throw UpdateError.unpackFailed
        }
        guard let app = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInArchive
        }
        return app
    }

    /// Puts the new app where the running one is. The running app keeps
    /// working until it quits; on failure nothing is changed.
    private static func replaceCurrentApp(with newApp: URL) throws -> URL {
        let current = Bundle.main.bundleURL
        return try FileManager.default.replaceItemAt(current, withItemAt: newApp) ?? current
    }

    /// Opens the new app once this one has quit, then quits.
    private static func relaunch(_ app: URL) {
        let quoted = "'" + app.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        _ = run("/bin/sh", ["-c", "sleep 1; /usr/bin/open -n \(quoted)"], wait: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exit(0)
        }
    }

    /// When the app can't be swapped in place: the releases page, to install
    /// the beta by hand.
    private static func offerManualInstall(_ release: IvyMacBetaRelease) {
        guard let presenter = CurrentAppContext().frontmostViewController() else {
            return
        }
        let sheet = ActionSheetController(
            title: IvyLocalizedString("MAC_BETA_UPDATE_FAILED_TITLE", comment: "Title when Ivy couldn't install the newer Mac beta by itself."),
            message: IvyLocalizedString("MAC_BETA_UPDATE_FAILED_MESSAGE", comment: "Explains how to install the Mac beta by hand when the updater couldn't."),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("MAC_BETA_UPDATE_OPEN_RELEASES", comment: "Button that opens the releases page with the Mac beta download."),
            style: .default,
        ) { _ in
            UIApplication.shared.open(IvyMacBetaRelease.releasesPageURL)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presenter.presentActionSheet(sheet)
    }

    private static func showMessage(_ message: String) {
        guard let presenter = CurrentAppContext().frontmostViewController() else {
            return
        }
        presenter.presentToast(text: message)
    }

    /// Runs a system tool; returns its exit status (0 when not waiting).
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String], wait: Bool = true) -> Int32 {
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = ([tool] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        guard posix_spawn(&pid, tool, nil, nil, argv, envp) == 0 else {
            return -1
        }
        guard wait else {
            return 0
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return (status >> 8) & 0xff
    }
}

#endif
