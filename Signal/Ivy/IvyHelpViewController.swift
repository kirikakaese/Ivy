//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

/// Settings > Help. Signal does not support Ivy, so instead of Signal's
/// support center and contact form this points to Ivy's issue tracker, and
/// debug logs are exported instead of uploaded.
final class IvyHelpViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: CommonStrings.help)

        let supportSection = OWSTableSection()
        supportSection.add(.disclosureItem(
            withText: IvyLocalizedString("HELP_REPORT_PROBLEM", comment: "Help item that opens Ivy's issue tracker."),
            actionBlock: { [weak self] in
                self?.present(SFSafariViewController(url: IvyConfiguration.issuesURL), animated: true)
            },
        ))
        contents.add(supportSection)

        let loggingSection = OWSTableSection()
        loggingSection.headerTitle = OWSLocalizedString("LOGGING_SECTION", comment: "Title for the 'logging' help section.")
        loggingSection.footerTitle = IvyLocalizedString(
            "HELP_DEBUG_LOG_FOOTER",
            comment: "Footer of the debug log section in Help, explaining that logs stay on the device.",
        )
        loggingSection.add(.item(
            name: IvyLocalizedString("HELP_EXPORT_DEBUG_LOG", comment: "Help item that previews and exports the debug log."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "export_debug_log"),
            actionBlock: { [weak self] in
                guard let self else { return }
                DebugLogs(dumper: .fromGlobals()).promptToSubmitLogs(from: self)
            },
        ))
        contents.add(loggingSection)

        let aboutSection = OWSTableSection()
        aboutSection.headerTitle = OWSLocalizedString("ABOUT_SECTION_TITLE", comment: "Title for the 'about' help section")
        aboutSection.add(.disclosureItem(
            withText: IvyLocalizedString("ABOUT_IVY_TITLE", comment: "Title of the About Ivy screen and the item that opens it."),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(AboutIvyViewController(), animated: true)
            },
        ))
        aboutSection.add(.disclosureItem(
            withText: OWSLocalizedString("SETTINGS_LEGAL_TERMS_CELL", comment: ""),
            actionBlock: { [weak self] in
                self?.present(SFSafariViewController(url: TSConstants.legalTermsUrl), animated: true)
            },
        ))
        contents.add(aboutSection)

        self.contents = contents
    }
}
