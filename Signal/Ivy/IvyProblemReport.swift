//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// "Report a Problem": a sheet with a screenshot of where the user was, a
/// text field and the debug log, which opens a new issue on Ivy's issue
/// page. GitHub's new-issue link can't carry files, so the screenshot is
/// copied for pasting and the debug log is saved first for attaching.
/// Nothing is sent anywhere by Ivy itself.
enum IvyProblemReport {

    private static let shakeKey = "IvyShakeToReport"

    /// Whether shaking the iPhone opens the sheet. On by default.
    static var opensOnShake: Bool {
        get { UserDefaults.standard.object(forKey: shakeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: shakeKey) }
    }

    /// Listens for shakes (reported by OWSWindow).
    static func start() {
        NotificationCenter.default.addObserver(
            forName: .ivyDeviceShaken,
            object: nil,
            queue: .main,
        ) { notification in
            MainActor.assumeIsolated {
                guard opensOnShake, let window = notification.object as? UIWindow else { return }
                present(capturing: window)
            }
        }
    }

    /// Opens the sheet over the frontmost screen, with a screenshot of the
    /// window taken just before.
    @MainActor
    static func present(capturing window: UIWindow?) {
        guard let presenter = CurrentAppContext().frontmostViewController() else { return }
        if presenter is IvyProblemReportViewController || presenter.children.contains(where: { $0 is IvyProblemReportViewController }) {
            return
        }
        let screenshot = window.flatMap(screenshot(of:))
        let report = IvyProblemReportViewController(screenshot: screenshot)
        let navigation = OWSNavigationController(rootViewController: report)
        presenter.present(navigation, animated: true)
    }

    @MainActor
    private static func screenshot(of window: UIWindow) -> UIImage? {
        guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    // MARK: Issue

    /// The issue title: the first line of the description, shortened.
    static func title(from description: String, fallback: String) -> String {
        let firstLine = description
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return fallback }
        guard firstLine.count > 70 else { return firstLine }
        return String(firstLine.prefix(69)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The body of the new issue.
    static func body(description: String, hints: [String], details: String) -> String {
        var lines = [description.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !hints.isEmpty {
            lines.append("")
            lines.append(contentsOf: hints)
        }
        lines.append("")
        lines.append("---")
        lines.append(details)
        return lines.joined(separator: "\n")
    }

    /// The link to a new issue with the title and body filled in.
    static func issueURL(title: String, body: String) -> URL? {
        guard var components = URLComponents(
            url: IvyConfiguration.issuesURL.appendingPathComponent("new"),
            resolvingAgainstBaseURL: false,
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
        ]
        // "+" would be read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// App, system and device, for the end of the issue.
    static var deviceDetails: String {
        "Ivy \(AppVersionImpl.shared.currentAppVersion) · iOS \(AppVersionImpl.shared.iosVersionString) · \(UIDevice.current.model)"
    }
}

// MARK: - Sheet

final class IvyProblemReportViewController: UIViewController, UITextViewDelegate {

    private let screenshot: UIImage?
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let screenshotSwitch = UISwitch()
    private let logSwitch = UISwitch()
    private let submitButton = UIButton(type: .system)
    private let scrollView = UIScrollView()

    init(screenshot: UIImage?) {
        self.screenshot = screenshot
        super.init(nibName: nil, bundle: nil)
        title = IvyLocalizedString("HELP_REPORT_PROBLEM", comment: "Help item that opens Ivy's issue tracker.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.groupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        if let screenshot {
            let imageView = UIImageView(image: screenshot)
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .Signal.secondaryGroupedBackground
            imageView.layer.cornerRadius = 14
            imageView.clipsToBounds = true
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = IvyLocalizedString(
                "REPORT_PROBLEM_SCREENSHOT_A11Y",
                comment: "Accessibility label of the screenshot preview in Report a Problem.",
            )
            imageView.heightAnchor.constraint(equalToConstant: 200).isActive = true
            stack.addArrangedSubview(imageView)
        }

        textView.font = .dynamicTypeBody
        textView.backgroundColor = .Signal.secondaryGroupedBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.delegate = self
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        textView.isScrollEnabled = false
        placeholder.text = IvyLocalizedString(
            "REPORT_PROBLEM_PLACEHOLDER",
            comment: "Placeholder of the text field in Report a Problem.",
        )
        placeholder.font = .dynamicTypeBody
        placeholder.textColor = .Signal.secondaryLabel
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
        ])
        textView.accessibilityLabel = placeholder.text
        stack.addArrangedSubview(textView)

#if targetEnvironment(macCatalyst)
        // Switches on the Mac too, not checkboxes.
        for toggle in [screenshotSwitch, logSwitch] {
            toggle.preferredStyle = .sliding
            toggle.onTintColor = .Signal.accent
        }
#endif
        if screenshot != nil {
            screenshotSwitch.isOn = true
            stack.addArrangedSubview(switchRow(
                title: IvyLocalizedString(
                    "REPORT_PROBLEM_ATTACH_SCREENSHOT",
                    comment: "Switch in Report a Problem that includes the screenshot.",
                ),
                toggle: screenshotSwitch,
            ))
        }
        logSwitch.isOn = true
        stack.addArrangedSubview(switchRow(
            title: IvyLocalizedString(
                "REPORT_PROBLEM_ATTACH_LOG",
                comment: "Switch in Report a Problem that includes the debug log, which contains no message contents.",
            ),
            toggle: logSwitch,
        ))

        var configuration = UIButton.Configuration.filled()
        configuration.title = IvyLocalizedString(
            "REPORT_PROBLEM_SUBMIT",
            comment: "Button in Report a Problem that opens a new issue on GitHub.",
        )
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        submitButton.configuration = configuration
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .primaryActionTriggered)
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(submitButton)

        let footer = UILabel()
        footer.numberOfLines = 0
        footer.font = .dynamicTypeFootnote
        footer.textColor = .Signal.secondaryLabel
        footer.text = IvyLocalizedString(
            "REPORT_PROBLEM_FOOTER",
            comment: "Explanation under the button in Report a Problem: what happens with the text, screenshot and debug log.",
        )
        stack.addArrangedSubview(footer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func switchRow(title: String, toggle: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.spacing = 12
        row.alignment = .center
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.accessibilityLabel = title
        return row
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
    }

    // MARK: Submitting

    private func submit() {
        let description = textView.text ?? ""
        let includesScreenshot = screenshot != nil && screenshotSwitch.isOn
        let includesLog = logSwitch.isOn

        var hints: [String] = []
        if includesScreenshot, let screenshot {
            UIPasteboard.general.image = screenshot
            hints.append(IvyLocalizedString(
                "REPORT_PROBLEM_BODY_SCREENSHOT",
                comment: "Line in a new issue where the user pastes the copied screenshot.",
            ))
        }
        if includesLog {
            hints.append(IvyLocalizedString(
                "REPORT_PROBLEM_BODY_LOG",
                comment: "Line in a new issue where the user attaches the saved debug log.",
            ))
        }
        let title = IvyProblemReport.title(
            from: description,
            fallback: IvyLocalizedString("REPORT_PROBLEM_DEFAULT_TITLE", comment: "Title of a new issue when the user wrote nothing."),
        )
        let body = IvyProblemReport.body(description: description, hints: hints, details: IvyProblemReport.deviceDetails)
        guard let url = IvyProblemReport.issueURL(title: title, body: body) else { return }

        textView.resignFirstResponder()
        submitButton.isEnabled = false
        Task { @MainActor in
            if includesLog {
                await DebugLogs(dumper: .fromGlobals()).exportLogs(from: self)
            }
            await self.awaitableDismiss(animated: true)
            await UIApplication.shared.open(url)
        }
    }
}
