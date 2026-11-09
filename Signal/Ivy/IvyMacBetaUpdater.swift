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
    private static let autoCheckKey = "IvyMacBetaChecksAutomatically"
    private static var isBusy = false

    /// What the updater is doing, for Settings > Updates.
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(IvyMacBetaRelease)
        case downloading(IvyMacBetaRelease, progress: Double)
        case installing(IvyMacBetaRelease)
        case failed
    }

    static let stateDidChange = Notification.Name("IvyMacBetaUpdaterStateDidChange")

    private(set) static var state: State = .idle {
        didSet {
            NotificationCenter.default.post(name: stateDidChange, object: nil)
        }
    }

    /// Whether Ivy looks for a newer beta by itself. On by default.
    static var checksAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    /// When Ivy last looked for a newer beta.
    static var lastCheck: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

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
        guard checksAutomatically else {
            return
        }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > checkInterval else {
            return
        }
        Task { await check(userInitiated: false) }
    }

    /// Looks for a newer beta. Asked for by hand, it also says when there is
    /// none, and offers a version skipped before. From Settings > Updates
    /// (`quietly`), the page shows the outcome instead of a sheet.
    static func check(userInitiated: Bool, quietly: Bool = false) async {
        guard isAvailable, !isBusy, let current = IvyMacBetaRelease.currentNumber else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        state = .checking
        let newest: IvyMacBetaRelease?
        do {
            var request = URLRequest(url: IvyMacBetaRelease.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            newest = IvyMacBetaRelease.newest(inReleasesJSON: data)
        } catch {
            Logger.warn("Couldn't look for a Mac beta update: \(error)")
            state = .failed
            if userInitiated, !quietly {
                showMessage(IvyLocalizedString("MAC_BETA_UPDATE_CHECK_FAILED", comment: "Shown when Ivy couldn't look for a newer Mac beta."))
            }
            return
        }
        guard let newest, newest.number > current else {
            state = .upToDate
            if userInitiated, !quietly {
                showMessage(String(
                    format: IvyLocalizedString("MAC_BETA_UP_TO_DATE_FORMAT", comment: "Shown when the Mac beta is the newest one. Embeds {{ beta number }}."),
                    current,
                ))
            }
            return
        }
        state = .available(newest)
        if quietly || (!userInitiated && UserDefaults.standard.integer(forKey: skippedKey) == newest.number) {
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
            showUpdatesPage()
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

    /// Downloads and installs a beta, then restarts Ivy. Settings >
    /// Updates shows the progress.
    static func install(_ release: IvyMacBetaRelease) async {
        guard !isBusy else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        state = .downloading(release, progress: 0)
        do {
            let newApp = try await download(release)
            state = .installing(release)
            let installed = try replaceCurrentApp(with: newApp)
            relaunch(installed)
        } catch {
            Logger.warn("Couldn't install Mac beta \(release.number): \(error)")
            state = .available(release)
            offerManualInstall(release)
        }
    }

    /// Downloads, checks and unpacks the beta; returns the unpacked app.
    private static func download(_ release: IvyMacBetaRelease) async throws -> URL {
        let file = try await IvyDownload.run(release.zipURL) { progress in
            state = .downloading(release, progress: progress)
        }
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

    /// Opens Settings > Updates.
    static func showUpdatesPage() {
        guard let presenter = CurrentAppContext().frontmostViewController() else {
            return
        }
        if let navigation = presenter as? UINavigationController, navigation.topViewController is IvyMacUpdatesViewController {
            return
        }
        let navigation = AppSettingsViewController.inModalNavigationController()
        navigation.pushViewController(IvyMacUpdatesViewController(), animated: false)
        presenter.presentFormSheet(navigation, animated: true)
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

/// A download that reports its progress (0 to 1) on the main thread.
private final class IvyDownload: NSObject, URLSessionDownloadDelegate {

    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @MainActor (Double) -> Void

    private init(onProgress: @escaping @MainActor (Double) -> Void) {
        self.onProgress = onProgress
    }

    @MainActor
    static func run(_ url: URL, onProgress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let delegate = IvyDownload(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        MainActor.assumeIsolated { onProgress(progress) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is removed when this returns, so it moves first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else if let response = task.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            continuation.resume(throwing: URLError(.badServerResponse))
        } else {
            continuation.resume(throwing: URLError(.unknown))
        }
    }
}

#endif
