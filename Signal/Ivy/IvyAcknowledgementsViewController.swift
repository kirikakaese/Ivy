//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The licenses of the libraries Ivy uses, from the acknowledgements that the
/// dependency install writes for the iOS Settings app. The Mac has no Settings
/// app page, so they are shown here on every platform.
final class IvyAcknowledgementsViewController: OWSTableViewController2 {

    struct Acknowledgement {
        let title: String
        let text: String
    }

    static func loadAcknowledgements(bundle: Bundle = .main.app) -> [Acknowledgement] {
        guard
            let url = bundle.url(forResource: "Acknowledgements", withExtension: "plist", subdirectory: "Settings.bundle"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let specifiers = plist["PreferenceSpecifiers"] as? [[String: Any]]
        else {
            return []
        }
        return specifiers.compactMap { specifier in
            // Entries without a title, such as the dependency manager's note at the
            // end, are not licenses.
            guard
                let title = specifier["Title"] as? String,
                let text = specifier["FooterText"] as? String,
                !title.isEmpty,
                !text.isEmpty
            else {
                return nil
            }
            return Acknowledgement(title: title, text: text)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let contents = OWSTableContents(title: IvyLocalizedString(
            "ABOUT_THIRD_PARTY_LICENSES",
            comment: "Item that lists the licenses of the libraries Ivy uses.",
        ))
        let section = OWSTableSection()
        for acknowledgement in Self.loadAcknowledgements() {
            section.add(.disclosureItem(
                withText: acknowledgement.title,
                maxNameLines: 2,
                actionBlock: { [weak self] in
                    let viewController = IvyLicenseTextViewController(title: acknowledgement.title, text: acknowledgement.text)
                    self?.navigationController?.pushViewController(viewController, animated: true)
                },
            ))
        }
        contents.add(section)
        self.contents = contents
    }
}

private final class IvyLicenseTextViewController: UIViewController {

    private let text: String

    init(title: String, text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.background

        let textView = UITextView()
        textView.text = text
        textView.isEditable = false
        textView.font = .dynamicTypeFootnote
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .Signal.label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(hMargin: 16, vMargin: 16)
        view.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()
    }
}
