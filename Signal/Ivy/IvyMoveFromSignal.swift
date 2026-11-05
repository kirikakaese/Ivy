//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Moving from Signal on the same iPhone: Signal's transfer needs a second
/// device to scan a QR code, so this guide takes the backup route instead.
/// Signal Backups on, the recovery key copied, then Ivy restores from the
/// backup after the phone number is confirmed.
final class IvyMoveFromSignalViewController: OWSViewController {

    private let onContinue: () -> Void

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.background

        let title = UILabel.titleLabelForRegistration(text: IvyLocalizedString("MOVE_FROM_SIGNAL_TITLE", comment: "Title of the guide for moving from Signal on the same iPhone."))
        let subtitle = UILabel.explanationLabelForRegistration(text: IvyLocalizedString("MOVE_FROM_SIGNAL_SUBTITLE", comment: "Subtitle of the guide for moving from Signal on the same iPhone."))

        let steps = UIStackView(arrangedSubviews: [
            Self.step(1, IvyLocalizedString("MOVE_FROM_SIGNAL_STEP1_TITLE", comment: "Step 1 of moving from Signal: turn on Signal Backups."),
                      IvyLocalizedString("MOVE_FROM_SIGNAL_STEP1_TEXT", comment: "Step 1 of moving from Signal: where Signal Backups are in Signal.")),
            Self.step(2, IvyLocalizedString("MOVE_FROM_SIGNAL_STEP2_TITLE", comment: "Step 2 of moving from Signal: copy the recovery key."),
                      IvyLocalizedString("MOVE_FROM_SIGNAL_STEP2_TEXT", comment: "Step 2 of moving from Signal: where the recovery key is in Signal.")),
            Self.step(3, IvyLocalizedString("MOVE_FROM_SIGNAL_STEP3_TITLE", comment: "Step 3 of moving from Signal: come back to Ivy."),
                      IvyLocalizedString("MOVE_FROM_SIGNAL_STEP3_TEXT", comment: "Step 3 of moving from Signal: confirm the phone number, choose the backup and paste the key.")),
        ])
        steps.axis = .vertical
        steps.spacing = 20

        let note = UILabel.explanationLabelForRegistration(text: IvyLocalizedString("MOVE_FROM_SIGNAL_NOTE", comment: "Note in the guide for moving from Signal: switch to Signal without closing Ivy."))
        note.font = .dynamicTypeFootnote

        let continueButton = UIButton(
            configuration: .largePrimary(title: IvyLocalizedString("MOVE_FROM_SIGNAL_CONTINUE", comment: "Button in the guide for moving from Signal once the recovery key is copied.")),
            primaryAction: UIAction { [weak self] _ in
                self?.onContinue()
            },
        )
        let cancelButton = UIButton(
            configuration: .mediumSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            },
        )

        let stack = UIStackView(arrangedSubviews: [title, subtitle, steps, note, UIView(), continueButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(8, after: continueButton)

        let scroll = UIScrollView()
        view.addSubview(scroll)
        scroll.autoPinEdgesToSuperviewSafeArea()
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor, constant: -56),
        ])
    }

    private static func step(_ number: Int, _ title: String, _ text: String) -> UIView {
        let badge = UILabel()
        badge.text = "\(number)"
        badge.font = .dynamicTypeSubheadline.semibold()
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = .Signal.accent
        badge.layer.cornerRadius = 13
        badge.clipsToBounds = true
        badge.autoSetDimensions(to: CGSize(square: 26))

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0
        let textLabel = UILabel()
        textLabel.text = text
        textLabel.font = .dynamicTypeSubheadline
        textLabel.textColor = .Signal.secondaryLabel
        textLabel.numberOfLines = 0
        let texts = UIStackView(arrangedSubviews: [titleLabel, textLabel])
        texts.axis = .vertical
        texts.spacing = 2

        let badgeColumn = UIStackView(arrangedSubviews: [badge, UIView()])
        badgeColumn.axis = .vertical
        let row = UIStackView(arrangedSubviews: [badgeColumn, texts])
        row.spacing = 12
        row.alignment = .top
        return row
    }
}

/// A system paste button under the recovery key: it pastes without Apple's
/// "Allow Paste" question, and the key is formatted as if typed.
@available(iOS 16, *)
final class IvyRecoveryKeyPasteButton: UIView, UIPasteConfigurationSupporting {

    private let onPaste: (String) -> Void

    init(onPaste: @escaping (String) -> Void) {
        self.onPaste = onPaste
        super.init(frame: .zero)
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: ["public.plain-text"])
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .capsule
        let control = UIPasteControl(configuration: configuration)
        control.target = self
        addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
            control.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let text = object as? String else { return }
            DispatchQueue.main.async { self?.onPaste(text) }
        }
    }
}
