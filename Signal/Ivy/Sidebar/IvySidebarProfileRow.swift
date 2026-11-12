//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The bottom of the Mac's sidebar: the profile picture and name, which
/// open Settings. It takes the place of the profile picture above the
/// chat list.
final class IvySidebarProfileRow: UIControl {

    private static let avatarSize: UInt = 26

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let separator = UIView()
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        separator.backgroundColor = .Signal.opaqueSeparator.withAlphaComponent(0.5)
        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = CGFloat(Self.avatarSize) / 2
        avatarView.clipsToBounds = true

        nameLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        nameLabel.textColor = .Signal.label
        detailLabel.font = .dynamicTypeCaption1Clamped
        detailLabel.textColor = .Signal.secondaryLabel
        detailLabel.text = IvyLocalizedString("SIDEBAR_PROFILE_DETAIL", comment: "Under the user's name at the bottom of the Mac sidebar, which opens the profile and Settings.")

        let texts = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 0
        let gear = UIImageView(image: UIImage(systemName: "gearshape"))
        gear.tintColor = .Signal.secondaryLabel
        gear.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        gear.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [avatarView, texts, gear])
        row.spacing = 9
        row.alignment = .center
        row.isUserInteractionEnabled = false

        for subview in [separator, row] {
            addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            avatarView.widthAnchor.constraint(equalToConstant: CGFloat(Self.avatarSize)),
            avatarView.heightAnchor.constraint(equalToConstant: CGFloat(Self.avatarSize)),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = CommonStrings.openAppSettingsButton
        toolTip = CommonStrings.openAppSettingsButton
        // A plain control sends no primary action on the Mac, only clicks.
        addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)

        NotificationCenter.default.addObserver(self, selector: #selector(update), name: UserProfileNotifications.localProfileDidChange, object: nil)
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .Signal.secondaryFill : nil
        }
    }

    @objc
    private func update() {
        let (name, avatar) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let profile = SSKEnvironment.shared.profileManagerRef.localUserProfile(tx: tx)
            let avatar = SSKEnvironment.shared.avatarBuilderRef.avatarImageForLocalUser(
                diameterPoints: Self.avatarSize,
                localUserDisplayMode: .asUser,
                transaction: tx,
            )
            return (profile?.filteredFullName?.nilIfEmpty, avatar)
        }
        nameLabel.text = name ?? CommonStrings.openAppSettingsButton
        avatarView.image = avatar
        accessibilityLabel = name ?? CommonStrings.openAppSettingsButton
    }
}

// MARK: - Leading title

extension UIViewController {

    /// On the Mac, while the sidebar shows: the screen's title on the left
    /// of its bar, instead of the profile picture there and the title in
    /// the middle. Returns whether it did so.
    func ivyMacUsesLeadingTitle(_ explicitTitle: String? = nil) -> Bool {
#if targetEnvironment(macCatalyst)
        guard (tabBarController as? HomeTabBarController)?.ivyIsSidebarShown == true, let title = explicitTitle ?? navigationItem.title ?? title else {
            if #available(iOS 16, *), navigationItem.style == .browser {
                navigationItem.style = .navigator
            }
            return false
        }
        // The title on the left of the bar, where the Mac puts it, at the
        // same margin as the search field and the list below.
        navigationItem.title = title
        navigationItem.leftBarButtonItem = nil
        navigationItem.titleView = nil
        if #available(iOS 16, *) {
            navigationItem.style = .browser
        }
        if let bar = navigationController?.navigationBar {
            bar.preservesSuperviewLayoutMargins = false
            bar.insetsLayoutMarginsFromSafeArea = false
            // The title came out 8 pt left of the pictures and labels in
            // the list below it; the wider leading margin moves it onto
            // their line.
            bar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: ChatListViewController.ivyMacMargin + 8, bottom: 0, trailing: ChatListViewController.ivyMacMargin)
        }
        return true
#else
        return false
#endif
    }
}

extension ChatListViewController {
    /// The Mac's margin on the left and right of the lists and their bars.
    static let ivyMacMargin: CGFloat = 16

    /// How far a selected chat's highlight is from the column's edges, as in
    /// the sidebar.
    static let ivyMacHighlightInset: CGFloat = 10

    /// From the highlight's edge to the pictures and the section labels, so
    /// they start 18 pt from the column's edge.
    static let ivyMacRowMargin: CGFloat = 8
}
