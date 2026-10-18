//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The chat folders as a row of chips above the chats, on the iPhone and a
/// narrow iPad. Where the window has a sidebar, the folders are in it
/// instead (see IvySidebarViewController).
final class ChatFolderBar: UIView {

    struct Item: Equatable {
        let folder: ChatFolder
        let unreadCount: Int
        var extras = ChatFolderExtras()
    }

    var onSelect: ((ChatFolder) -> Void)?
    var menuProvider: ((ChatFolder) -> UIMenu?)?
    var onEditFolders: (() -> Void)?

    private(set) var items: [Item] = []
    private(set) var selectedFolderId: Data?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init() {
        super.init(frame: .zero)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(items: [Item], selectedFolderId: Data?) {
        guard items != self.items || selectedFolderId != self.selectedFolderId else {
            return
        }
        self.items = items
        self.selectedFolderId = selectedFolderId
        reloadButtons()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 50)
    }

    // MARK: - Private

    private func reloadButtons() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            stackView.addArrangedSubview(chip(for: item))
        }
        stackView.addArrangedSubview(editButton())
    }

    /// A capsule with the folder's emoji, name and unread count. The open
    /// folder is filled with its color, the others are tinted with it.
    private func chip(for item: Item) -> UIButton {
        let isSelected = item.folder.id == selectedFolderId
        let color = item.extras.color.map(Self.uiColor(for:)) ?? .Signal.accent

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = isSelected ? color : color.withAlphaComponent(0.12)
        configuration.baseForegroundColor = isSelected ? .white : .Signal.label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)

        let title = Self.title(for: item.folder)
        var text = AttributedString((item.extras.emoji.map { $0 + "  " } ?? "") + title)
        text.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        if item.unreadCount > 0 {
            var count = AttributedString("  \(item.unreadCount.formatted())")
            count.font = UIFont.dynamicTypeCaption1Clamped.semibold()
            count.foregroundColor = isSelected ? UIColor.white.withAlphaComponent(0.85) : color
            text += count
        }
        configuration.attributedTitle = text

        let folder = item.folder
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onSelect?(folder)
        })
        button.menu = menuProvider?(folder)
        button.isSelected = isSelected
        button.accessibilityLabel = title
        if item.unreadCount > 0 {
            button.accessibilityValue = String.localizedStringWithFormat(
                IvyLocalizedString("CHAT_FOLDER_UNREAD_COUNT_FORMAT", comment: "Accessibility value of a chat folder tab. Embeds {{ the number of chats with unread messages }}."),
                item.unreadCount,
            )
        }
        if isSelected {
            button.accessibilityTraits.insert(.selected)
        }
        return button
    }

    private func editButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "slider.horizontal.3")
        configuration.baseForegroundColor = .Signal.secondaryLabel
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onEditFolders?()
        })
        button.accessibilityLabel = IvyLocalizedString("CHAT_FOLDERS_EDIT", comment: "Button that opens the chat folder settings.")
        return button
    }

    static func uiColor(for color: ChatFolderColor) -> UIColor {
        switch color {
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .gray: return .systemGray
        }
    }

    /// An emoji drawn as an image, for the sidebar.
    static func image(emoji: String) -> UIImage {
        let font = UIFont.systemFont(ofSize: 20)
        let text = emoji as NSString
        let size = text.size(withAttributes: [.font: font])
        return UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(at: .zero, withAttributes: [.font: font])
        }.withRenderingMode(.alwaysOriginal)
    }

    static func title(for folder: ChatFolder) -> String {
        switch folder.kind {
        case .allChats:
            return IvyLocalizedString("CHAT_FOLDER_ALL_CHATS", comment: "Name of the chat folder that shows every chat.")
        case .custom:
            return folder.name
        }
    }
}
