//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

#if targetEnvironment(macCatalyst)

import SignalServiceKit
import SignalUI

/// Settings > Updates on the Mac beta: the installed beta, checking by hand
/// or automatically, and a newer beta with what changed, its download and
/// "Install and Restart".
final class IvyMacUpdatesViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: IvyMacBetaUpdater.stateDidChange, object: nil)
        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Opening the page looks once, unless that just happened.
        if IvyMacBetaUpdater.state == .idle {
            Task { await IvyMacBetaUpdater.check(userInitiated: true, quietly: true) }
        }
    }

    static var title: String {
        IvyLocalizedString("MAC_UPDATES_TITLE", comment: "Title of the Mac beta's Updates page in Settings.")
    }

    @objc
    private func stateDidChange() {
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: Self.title)
        let state = IvyMacBetaUpdater.state

        let installed = OWSTableSection()
        let number = IvyMacBetaRelease.currentNumber.map(String.init) ?? "–"
        installed.add(Self.row(
            title: IvyLocalizedString("MAC_UPDATES_INSTALLED", comment: "Row on the Updates page: the installed Mac beta."),
            detail: String(
                format: IvyLocalizedString("MAC_UPDATES_INSTALLED_FORMAT", comment: "The installed Mac beta and app version. Embeds {{ beta number }} and {{ version }}."),
                number,
                AppVersionImpl.shared.currentAppVersion,
            ),
            accessory: Self.statusText(for: state),
        ))
        installed.add(.switch(
            withText: IvyLocalizedString("MAC_UPDATES_AUTOMATIC", comment: "Switch on the Updates page: look for a newer Mac beta automatically."),
            isOn: { IvyMacBetaUpdater.checksAutomatically },
            actionBlock: { sender in IvyMacBetaUpdater.checksAutomatically = sender.isOn },
        ))
        let isChecking = state == .checking
        installed.add(Self.row(
            title: isChecking
                ? IvyLocalizedString("MAC_UPDATES_CHECKING", comment: "Shown on the Updates page while Ivy looks for a newer Mac beta.")
                : IvyLocalizedString("MAC_UPDATES_CHECK_NOW", comment: "Button on the Updates page that looks for a newer Mac beta now."),
            detail: Self.lastCheckText(),
            titleColor: isChecking ? .Signal.secondaryLabel : .Signal.accent,
            action: isChecking ? nil : {
                Task { await IvyMacBetaUpdater.check(userInitiated: true, quietly: true) }
            },
        ))
        contents.add(installed)

        if let release = Self.release(in: state) {
            let newVersion = OWSTableSection()
            newVersion.headerTitle = IvyLocalizedString("MAC_UPDATES_NEW_VERSION", comment: "Header on the Updates page above a newer Mac beta.")
            newVersion.add(Self.row(
                title: String(
                    format: IvyLocalizedString("MAC_BETA_UPDATE_TITLE_FORMAT", comment: "Title when a newer Mac beta is out. Embeds {{ beta number }}."),
                    release.number,
                ),
                detail: release.changes.isEmpty ? nil : release.changes.map { "• " + $0 }.joined(separator: "\n"),
                isTitleBold: true,
            ))
            switch state {
            case .downloading(_, let progress):
                newVersion.add(Self.progressRow(progress))
            case .installing:
                newVersion.add(Self.row(
                    title: IvyLocalizedString("MAC_UPDATES_INSTALLING", comment: "Shown on the Updates page while the new Mac beta is put in place."),
                    titleColor: .Signal.secondaryLabel,
                ))
            default:
                newVersion.add(Self.row(
                    title: IvyLocalizedString("MAC_UPDATES_INSTALL", comment: "Button on the Updates page that downloads the new Mac beta, installs it and restarts Ivy."),
                    titleColor: .Signal.accent,
                    action: {
                        Task { await IvyMacBetaUpdater.install(release) }
                    },
                ))
            }
            newVersion.footerTitle = IvyLocalizedString("MAC_BETA_UPDATE_MESSAGE", comment: "Explains updating the Mac beta: Ivy restarts, and macOS may ask once to open it.")
            contents.add(newVersion)
        }

        self.contents = contents
    }

    // MARK: - Rows

    private static func release(in state: IvyMacBetaUpdater.State) -> IvyMacBetaRelease? {
        switch state {
        case .available(let release), .downloading(let release, _), .installing(let release):
            return release
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    private static func statusText(for state: IvyMacBetaUpdater.State) -> String? {
        switch state {
        case .upToDate:
            return IvyLocalizedString("MAC_UPDATES_UP_TO_DATE", comment: "Beside the installed Mac beta on the Updates page: it is the newest.")
        case .available, .downloading, .installing:
            return IvyLocalizedString("MAC_UPDATES_AVAILABLE", comment: "Beside the installed Mac beta on the Updates page: a newer one is out.")
        case .failed:
            return IvyLocalizedString("MAC_UPDATES_FAILED", comment: "Beside the installed Mac beta on the Updates page: looking for a newer one failed.")
        case .idle, .checking:
            return nil
        }
    }

    private static func lastCheckText() -> String? {
        guard let last = IvyMacBetaUpdater.lastCheck else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return String(
            format: IvyLocalizedString("MAC_UPDATES_LAST_CHECK_FORMAT", comment: "Under the check button on the Updates page. Embeds {{ date and time }}."),
            formatter.string(from: last),
        )
    }

    private static func row(
        title: String,
        detail: String? = nil,
        accessory: String? = nil,
        titleColor: UIColor = .Signal.label,
        isTitleBold: Bool = false,
        action: (() -> Void)? = nil,
    ) -> OWSTableItem {
        OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                var content = UIListContentConfiguration.subtitleCell()
                content.text = title
                content.textProperties.color = titleColor
                if isTitleBold {
                    content.textProperties.font = UIFont.dynamicTypeBody.semibold()
                }
                content.secondaryText = detail
                content.secondaryTextProperties.color = .Signal.secondaryLabel
                content.secondaryTextProperties.numberOfLines = 0
                content.textToSecondaryTextVerticalPadding = 4
                cell.contentConfiguration = content
                if let accessory {
                    let label = UILabel()
                    label.text = accessory
                    label.font = .dynamicTypeSubheadline
                    label.textColor = .Signal.secondaryLabel
                    label.sizeToFit()
                    cell.accessoryView = label
                }
                cell.selectionStyle = action == nil ? .none : .default
                return cell
            },
            actionBlock: action,
        )
    }

    private static func progressRow(_ progress: Double) -> OWSTableItem {
        OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            let label = UILabel()
            label.font = .dynamicTypeSubheadline
            label.textColor = .Signal.secondaryLabel
            label.text = String(
                format: IvyLocalizedString("MAC_UPDATES_DOWNLOADING_FORMAT", comment: "Shown on the Updates page while the new Mac beta downloads. Embeds {{ percent }}."),
                Int((progress * 100).rounded()),
            )
            let bar = UIProgressView(progressViewStyle: .default)
            bar.progress = Float(progress)
            bar.progressTintColor = .Signal.accent
            let stack = UIStackView(arrangedSubviews: [bar, label])
            stack.axis = .vertical
            stack.spacing = 8
            cell.contentView.addSubview(stack)
            stack.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
            return cell
        })
    }
}

#endif
