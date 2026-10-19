//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import LocalAuthentication
import SignalServiceKit
import SignalUI

/// Unlocking with Ivy's passcode, when one is set (see `IvyPasscode`).
@MainActor
enum IvyPasscodeLock {

    static var isSet: Bool {
        SSKEnvironment.shared.databaseStorageRef.read { tx in IvyPasscode.isSet(tx: tx) }
    }

    /// Asks for Ivy's passcode over the lock screen. Nil when no passcode is
    /// set, so Screen Lock asks the device as usual.
    static func unlockIfSet(over viewController: UIViewController?) async -> ScreenLock.Outcome? {
        guard isSet, let viewController else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let entry = IvyPasscodeEntryViewController { outcome in
                continuation.resume(returning: outcome)
            }
            entry.modalPresentationStyle = .fullScreen
            viewController.present(entry, animated: false)
        }
    }

    static var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return nil
        }
        switch context.biometryType {
        case .faceID: return IvyLocalizedString("PASSCODE_FACE_ID", comment: "Name of Face ID.")
        case .touchID: return IvyLocalizedString("PASSCODE_TOUCH_ID", comment: "Name of Touch ID.")
        case .opticID: return IvyLocalizedString("PASSCODE_OPTIC_ID", comment: "Name of Optic ID.")
        default: return nil
        }
    }
}

// MARK: - Entering the passcode

final class IvyPasscodeEntryViewController: UIViewController, UITextFieldDelegate {

    private let onDone: (ScreenLock.Outcome) -> Void
    private let field = UITextField()
    private let messageLabel = UILabel()
    private let biometryButton = UIButton(type: .system)
    private var isFinished = false
    private var blockTimer: Timer?

    init(onDone: @escaping (ScreenLock.Outcome) -> Void) {
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.background

        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .Signal.accent
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)

        let titleLabel = UILabel()
        titleLabel.text = IvyLocalizedString("PASSCODE_ENTER", comment: "Title of the screen that asks for Ivy's passcode.")
        titleLabel.font = .dynamicTypeTitle2.semibold()
        titleLabel.textAlignment = .center

        field.isSecureTextEntry = true
        field.textContentType = .password
        field.borderStyle = .roundedRect
        field.font = .dynamicTypeTitle3
        field.textAlignment = .center
        field.returnKeyType = .done
        field.delegate = self
        field.accessibilityLabel = titleLabel.text

        messageLabel.font = .dynamicTypeSubheadline
        messageLabel.textColor = .Signal.red
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        var unlock = UIButton.Configuration.filled()
        unlock.title = IvyLocalizedString("PASSCODE_UNLOCK", comment: "Button that unlocks Ivy with the entered passcode.")
        unlock.baseBackgroundColor = .Signal.accent
        unlock.cornerStyle = .large
        let unlockButton = UIButton(configuration: unlock, primaryAction: UIAction { [weak self] _ in self?.check() })

        let canUseBiometry = SSKEnvironment.shared.databaseStorageRef.read { tx in IvyPasscode.allowsBiometrics(tx: tx) }
        if canUseBiometry, let name = IvyPasscodeLock.biometryName {
            biometryButton.setTitle(String(format: IvyLocalizedString("PASSCODE_USE_BIOMETRY_FORMAT", comment: "Button that unlocks with Face ID or Touch ID. Embeds {{ Face ID or Touch ID }}."), name), for: .normal)
            biometryButton.addAction(UIAction { [weak self] _ in self?.tryBiometry() }, for: .primaryActionTriggered)
        } else {
            biometryButton.isHidden = true
        }

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, field, messageLabel, unlockButton, biometryButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.setCustomSpacing(24, after: titleLabel)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The space between the top and the keyboard.
        let area = UILayoutGuide()
        view.addLayoutGuide(area)
        let centered = stack.centerYAnchor.constraint(equalTo: area.centerYAnchor)
        centered.priority = .defaultHigh
        NSLayoutConstraint.activate([
            area.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            area.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 300),
            centered,
            stack.topAnchor.constraint(greaterThanOrEqualTo: area.topAnchor, constant: 24),
        ])
        updateBlockedState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !biometryButton.isHidden {
            tryBiometry()
        } else {
            field.becomeFirstResponder()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        check()
        return false
    }

    private func check() {
        let passcode = field.text ?? ""
        guard !passcode.isEmpty else {
            return
        }
        let result = SSKEnvironment.shared.databaseStorageRef.write { tx in IvyPasscode.verify(passcode, tx: tx) }
        field.text = nil
        switch result {
        case .correct:
            finish(.success)
        case .wrong:
            messageLabel.text = IvyLocalizedString("PASSCODE_WRONG", comment: "Shown after entering a wrong Ivy passcode.")
        case .blocked:
            updateBlockedState()
        }
    }

    private func tryBiometry() {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: IvyLocalizedString("PASSCODE_BIOMETRY_REASON", comment: "Shown by Face ID or Touch ID when unlocking Ivy."),
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    self?.finish(.success)
                } else {
                    self?.field.becomeFirstResponder()
                }
            }
        }
    }

    /// While wrong attempts block the passcode, says how long.
    private func updateBlockedState() {
        blockTimer?.invalidate()
        guard let until = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in IvyPasscode.blockedUntil(tx: tx) }) else {
            field.isEnabled = true
            return
        }
        field.isEnabled = false
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        messageLabel.text = String(
            format: IvyLocalizedString("PASSCODE_BLOCKED_FORMAT", comment: "Shown after too many wrong Ivy passcodes. Embeds {{ how long to wait }}."),
            formatter.string(from: max(until.timeIntervalSinceNow, 1)) ?? "",
        )
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.updateBlockedState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        blockTimer = timer
    }

    private func finish(_ outcome: ScreenLock.Outcome) {
        guard !isFinished else {
            return
        }
        isFinished = true
        blockTimer?.invalidate()
        dismiss(animated: false) { [onDone] in
            onDone(outcome)
        }
    }
}

// MARK: - Settings

extension PrivacySettingsViewController {

    /// "Ivy Passcode", under Screen Lock.
    func ivyAddPasscodeItem(to section: OWSTableSection) {
        section.add(.disclosureItem(
            withText: IvyPasscodeSettingsViewController.title,
            accessoryText: IvyPasscodeLock.isSet
                ? IvyLocalizedString("PASSCODE_ON", comment: "Shown next to the Ivy passcode setting when a passcode is set.")
                : IvyLocalizedString("PASSCODE_OFF", comment: "Shown next to the Ivy passcode setting when no passcode is set."),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyPasscodeSettingsViewController(), animated: true)
            },
        ))
    }
}

/// Sets, changes or removes Ivy's passcode.
final class IvyPasscodeSettingsViewController: OWSTableViewController2 {

    static var title: String {
        IvyLocalizedString("PASSCODE_TITLE", comment: "Title of the setting for Ivy's own passcode.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        updateTableContents()
    }

    private func updateTableContents() {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let (isSet, allowsBiometrics) = databaseStorage.read { tx in
            (IvyPasscode.isSet(tx: tx), IvyPasscode.allowsBiometrics(tx: tx))
        }
        let contents = OWSTableContents(title: title)
        let section = OWSTableSection()
        section.footerTitle = IvyLocalizedString(
            "PASSCODE_FOOTER",
            comment: "Explains Ivy's own passcode.",
        )
        if isSet {
            if let biometryName = IvyPasscodeLock.biometryName {
                section.add(.switch(
                    withText: String(format: IvyLocalizedString("PASSCODE_ALLOW_BIOMETRY_FORMAT", comment: "Switch that lets Face ID or Touch ID unlock instead of the passcode. Embeds {{ Face ID or Touch ID }}."), biometryName),
                    isOn: { allowsBiometrics },
                    actionBlock: { uiSwitch in
                        databaseStorage.write { tx in IvyPasscode.setAllowsBiometrics(uiSwitch.isOn, tx: tx) }
                    },
                ))
            }
            section.add(.actionItem(
                withText: IvyLocalizedString("PASSCODE_CHANGE", comment: "Button that changes Ivy's passcode."),
            ) { [weak self] in
                self?.confirmCurrentPasscode { self?.askForNewPasscode() }
            })
            section.add(.actionItem(
                withText: IvyLocalizedString("PASSCODE_TURN_OFF", comment: "Button that removes Ivy's passcode."),
                textColor: .Signal.red,
            ) { [weak self] in
                self?.confirmCurrentPasscode {
                    databaseStorage.write { tx in IvyPasscode.remove(tx: tx) }
                    self?.updateTableContents()
                }
            })
        } else {
            section.add(.actionItem(
                withText: IvyLocalizedString("PASSCODE_SET", comment: "Button that sets Ivy's passcode."),
                textColor: .Signal.accent,
            ) { [weak self] in
                self?.askForNewPasscode()
            })
        }
        contents.add(section)
        self.contents = contents
    }

    private func confirmCurrentPasscode(then action: @escaping () -> Void) {
        let alert = UIAlertController(title: IvyLocalizedString("PASSCODE_ENTER", comment: "Title of the screen that asks for Ivy's passcode."), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.textContentType = .password
        }
        alert.addAction(UIAlertAction(title: CommonStrings.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: CommonStrings.continueButton, style: .default) { [weak self, weak alert] _ in
            let passcode = alert?.textFields?.first?.text ?? ""
            let result = SSKEnvironment.shared.databaseStorageRef.write { tx in IvyPasscode.verify(passcode, tx: tx) }
            switch result {
            case .correct:
                action()
            case .wrong, .blocked:
                self?.presentToast(text: IvyLocalizedString("PASSCODE_WRONG", comment: "Shown after entering a wrong Ivy passcode."))
            }
        })
        present(alert, animated: true)
    }

    private func askForNewPasscode() {
        let alert = UIAlertController(
            title: IvyLocalizedString("PASSCODE_NEW", comment: "Title of the dialog that sets a new Ivy passcode."),
            message: String(format: IvyLocalizedString("PASSCODE_NEW_MESSAGE_FORMAT", comment: "Explains the new passcode. Embeds {{ the minimum number of characters }}."), String(IvyPasscode.minimumLength)),
            preferredStyle: .alert,
        )
        for placeholder in [
            IvyLocalizedString("PASSCODE_NEW_PLACEHOLDER", comment: "Placeholder of the field for a new Ivy passcode."),
            IvyLocalizedString("PASSCODE_REPEAT_PLACEHOLDER", comment: "Placeholder of the field that repeats a new Ivy passcode."),
        ] {
            alert.addTextField { field in
                field.isSecureTextEntry = true
                field.textContentType = .newPassword
                field.placeholder = placeholder
            }
        }
        alert.addAction(UIAlertAction(title: CommonStrings.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: CommonStrings.doneButton, style: .default) { [weak self, weak alert] _ in
            let first = alert?.textFields?.first?.text ?? ""
            let second = alert?.textFields?.last?.text ?? ""
            guard first.count >= IvyPasscode.minimumLength, first == second else {
                self?.presentToast(text: IvyLocalizedString("PASSCODE_MISMATCH", comment: "Shown when the new Ivy passcodes don't match or are too short."))
                return
            }
            SSKEnvironment.shared.databaseStorageRef.write { tx in IvyPasscode.set(first, tx: tx) }
            if !ScreenLock.shared.isScreenLockEnabled() {
                // The passcode only counts with Screen Lock on.
                ScreenLock.shared.setIsScreenLockEnabled(true)
            }
            self?.updateTableContents()
        })
        present(alert, animated: true)
    }
}
