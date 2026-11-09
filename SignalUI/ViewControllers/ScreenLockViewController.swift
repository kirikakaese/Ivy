//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LocalAuthentication
import SignalServiceKit
import UIKit

@MainActor
public protocol ScreenLockViewDelegate: AnyObject {
    func unlockButtonWasTapped()
}

open class ScreenLockViewController: UIViewController {

    public enum UIState: CustomStringConvertible {
        case none
        case screenProtection // Shown while app is inactive or background, if enabled.
        case screenLock // Shown while app is active, if enabled.

        public var description: String {
            switch self {
            case .none:
                return "ScreenLockUIStateNone"
            case .screenProtection:
                return "ScreenLockUIStateScreenProtection"
            case .screenLock:
                return "ScreenLockUIStateScreenLock"
            }
        }
    }

    public weak var delegate: ScreenLockViewDelegate?

    // MARK: - UI

    private lazy var imageViewLogo = UIImageView(image: UIImage(named: "signal-logo-128-launch-screen"))
    private static var buttonHeight: CGFloat { 40 }
    private lazy var buttonUnlockUI = UIButton(
        configuration: .largePrimary(title: OWSLocalizedString(
            "SCREEN_LOCK_UNLOCK_SIGNAL",
            comment: "Label for button on lock screen that lets users unlock Signal.",
        )),
        primaryAction: UIAction { [weak self] _ in
            self?.unlockUIButtonTapped()
        },
    )

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.Signal.background

#if targetEnvironment(macCatalyst)
        // Ivy: on the Mac, the app icon with a title and a normal-sized
        // button on a soft glow, instead of a logo and a full-width bar.
        ivyBuildMacLayout()
#else
        view.addSubview(imageViewLogo)
        imageViewLogo.autoHCenterInSuperview()
        imageViewLogo.autoVCenterInSuperview()
        imageViewLogo.autoSetDimensions(to: .square(128))

        buttonUnlockUI.configuration?.baseForegroundColor = .Signal.label
        buttonUnlockUI.configuration?.baseBackgroundColor = .Signal.tertiaryFill
        view.addSubview(buttonUnlockUI)
        buttonUnlockUI.autoPinWidthToSuperview(withMargin: 50)
        buttonUnlockUI.autoPinBottomToSuperviewMargin(withInset: 65)
#endif

        updateUIWithState(.screenProtection)
    }

    // The "screen blocking" window has three possible states:
    //
    // * "Just a logo". Used when app is launching and in app switcher. Must
    // match the "Launch Screen" storyboard pixel-for-pixel.
    //
    // * "Screen Lock, local auth UI presented".
    //
    // * "Screen Lock, local auth UI not presented". Show "unlock" button.
    public func updateUIWithState(_ uiState: UIState) {
        AssertIsOnMainThread()

        guard isViewLoaded else { return }

        let shouldHaveScreenLock: Bool
        switch uiState {
        case .none:
            shouldHaveScreenLock = false
        case .screenProtection:
            shouldHaveScreenLock = false
        case .screenLock:
            shouldHaveScreenLock = true
        }

        buttonUnlockUI.isHidden = !shouldHaveScreenLock
        ivyMacLockTexts.forEach { $0.isHidden = !shouldHaveScreenLock } // Ivy
    }

    // MARK: - Ivy: Mac layout

    private var ivyMacLockTexts: [UIView] = []
    private let ivyGlowLayer = CAGradientLayer()

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ivyGlowLayer.frame = view.bounds
    }

#if targetEnvironment(macCatalyst)
    // Return unlocks too.
    override open var keyCommands: [UIKeyCommand]? {
        guard !buttonUnlockUI.isHidden else { return super.keyCommands }
        return [UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(ivyReturnPressed))]
    }

    override open var canBecomeFirstResponder: Bool { true }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
#endif

    @objc
    private func ivyReturnPressed() {
        unlockUIButtonTapped()
    }

    private func ivyBuildMacLayout() {
        view.backgroundColor = UIColor(rgbHex: 0x111311)
        ivyGlowLayer.type = .radial
        ivyGlowLayer.colors = [UIColor(rgbHex: 0x1D3A2A).cgColor, UIColor(rgbHex: 0x111311).cgColor]
        ivyGlowLayer.startPoint = CGPoint(x: 0.5, y: 0)
        ivyGlowLayer.endPoint = CGPoint(x: 1.1, y: 0.9)
        view.layer.insertSublayer(ivyGlowLayer, at: 0)

        // The app icon: the leaf on a green rounded square.
        let icon = UIView()
        icon.layer.cornerRadius = 18
        icon.layer.cornerCurve = .continuous
        icon.backgroundColor = UIColor(rgbHex: 0x2F8F5B)
        icon.layer.shadowColor = UIColor(rgbHex: 0x1F6B43).cgColor
        icon.layer.shadowOpacity = 0.45
        icon.layer.shadowRadius = 15
        icon.layer.shadowOffset = CGSize(width: 0, height: 10)
        imageViewLogo.image = imageViewLogo.image?.withRenderingMode(.alwaysTemplate)
        imageViewLogo.tintColor = .white
        imageViewLogo.contentMode = .scaleAspectFit
        icon.addSubview(imageViewLogo)
        imageViewLogo.autoCenterInSuperview()
        imageViewLogo.autoSetDimensions(to: .square(46))
        icon.autoSetDimensions(to: .square(76))

        let title = UILabel()
        title.text = IvyLocalizedString("LOCK_SCREEN_TITLE", comment: "Title of the Mac's lock screen while Ivy is locked.")
        title.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = IvyLocalizedString("LOCK_SCREEN_SUBTITLE", comment: "Line under the title of the Mac's lock screen.")
        subtitle.font = UIFont.systemFont(ofSize: 13)
        subtitle.textColor = UIColor(white: 1, alpha: 0.62)
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor(rgbHex: 0x3FB26F)
        configuration.baseForegroundColor = UIColor(rgbHex: 0x08150D)
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18)
        configuration.imagePadding = 8
        // The biometry type is only known after asking whether it can be used.
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let usesTouchID = context.biometryType == .touchID
        configuration.image = UIImage(systemName: usesTouchID ? "touchid" : "lock.open")
        configuration.attributedTitle = AttributedString(
            usesTouchID
                ? IvyLocalizedString("LOCK_SCREEN_UNLOCK_TOUCH_ID", comment: "Button on the Mac's lock screen that unlocks Ivy with Touch ID.")
                : OWSLocalizedString("SCREEN_LOCK_UNLOCK_SIGNAL", comment: "Label for button on lock screen that lets users unlock Signal."),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 13, weight: .semibold)]),
        )
        buttonUnlockUI.configuration = configuration

        let hint = UILabel()
        hint.text = IvyLocalizedString("LOCK_SCREEN_RETURN_HINT", comment: "Small hint under the unlock button on the Mac's lock screen: pressing Return also unlocks.")
        hint.font = UIFont.systemFont(ofSize: 11.5)
        hint.textColor = UIColor(white: 1, alpha: 0.4)

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, buttonUnlockUI, hint])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(18, after: icon)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(8, after: buttonUnlockUI)
        view.addSubview(stack)
        stack.autoCenterInSuperview()
        stack.autoPinWidthToSuperview(withMargin: 40, relation: .lessThanOrEqual)
        ivyMacLockTexts = [title, subtitle, hint]
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.defaultSupportedOrientations
    }

    private func unlockUIButtonTapped() {
        delegate?.unlockButtonWasTapped()
    }
}

#if DEBUG

@available(iOS 17, *)
#Preview("State: none") {
    let vc = ScreenLockViewController()
    vc.view.isHidden = false // force view to load
    vc.updateUIWithState(.none)
    return vc
}

@available(iOS 17, *)
#Preview("State: screenProtection") {
    let vc = ScreenLockViewController()
    vc.view.isHidden = false // force view to load
    vc.updateUIWithState(.screenLock)
    return vc
}

@available(iOS 17, *)
#Preview("State: screenLock") {
    let vc = ScreenLockViewController()
    vc.view.isHidden = false // force view to load
    vc.updateUIWithState(.screenProtection)
    return vc
}

#endif
