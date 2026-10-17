//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

/// Version, origin, license, privacy statement and the notice that Ivy is
/// not affiliated with Signal.
final class AboutIvyViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: IvyLocalizedString(
            "ABOUT_IVY_TITLE",
            comment: "Title of the About Ivy screen and the item that opens it.",
        ))

        let appSection = OWSTableSection()
        appSection.footerTitle = IvyLocalizedString(
            "ABOUT_NOT_AFFILIATED",
            comment: "Notice on the About Ivy screen that Ivy is independent from Signal.",
        )
        appSection.add(.copyableItem(
            label: OWSLocalizedString("SETTINGS_VERSION", comment: ""),
            value: IvyMacBeta.isEnabled
                ? String(
                    format: IvyLocalizedString("ABOUT_MAC_BETA_VERSION_FORMAT", comment: "Version of the Mac beta. Embeds {{ version number }}."),
                    AppVersionImpl.shared.prettyAppVersion,
                )
                : AppVersionImpl.shared.prettyAppVersion,
        ))
        appSection.add(.copyableItem(
            label: IvyLocalizedString("ABOUT_BASED_ON", comment: "Label for the upstream release Ivy is built on."),
            value: String(
                format: IvyLocalizedString(
                    "ABOUT_BASED_ON_VALUE",
                    comment: "The upstream release Ivy is built on. Embeds {{ version number }}.",
                ),
                AppVersionImpl.shared.currentAppVersion,
            ),
        ))
        appSection.add(.copyableItem(
            label: IvyLocalizedString("ABOUT_MAINTAINER", comment: "Label for the person who maintains Ivy."),
            value: IvyConfiguration.maintainer,
        ))
        contents.add(appSection)

        let licenseSection = OWSTableSection()
        licenseSection.footerTitle = IvyLocalizedString(
            "ABOUT_LICENSE_FOOTER",
            comment: "License notice on the About Ivy screen.",
        )
        licenseSection.add(.disclosureItem(
            withText: IvyLocalizedString("ABOUT_SOURCE_CODE", comment: "Item that opens Ivy's source code."),
            actionBlock: { [weak self] in
                self?.present(SFSafariViewController(url: IvyConfiguration.sourceCodeURL), animated: true)
            },
        ))
        licenseSection.add(.disclosureItem(
            withText: IvyLocalizedString("ABOUT_LICENSE", comment: "Item that opens Ivy's license."),
            actionBlock: { [weak self] in
                self?.present(SFSafariViewController(url: IvyConfiguration.licenseURL), animated: true)
            },
        ))
        licenseSection.add(.disclosureItem(
            withText: IvyLocalizedString("ABOUT_THIRD_PARTY_LICENSES", comment: "Item that lists the licenses of the libraries Ivy uses."),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyAcknowledgementsViewController(), animated: true)
            },
        ))
        contents.add(licenseSection)

        let privacySection = OWSTableSection()
        privacySection.headerTitle = IvyLocalizedString("ABOUT_PRIVACY_TITLE", comment: "Title of the privacy statement on the About Ivy screen.")
        privacySection.footerTitle = IvyLocalizedString("ABOUT_PRIVACY_STATEMENT", comment: "Ivy's privacy statement on the About Ivy screen.")
        contents.add(privacySection)

        self.contents = contents
    }
}
