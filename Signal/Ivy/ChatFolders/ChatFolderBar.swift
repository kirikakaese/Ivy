//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The folder list of the chat list: scrollable tabs above the chats on
/// iPhone, a sidebar next to them on iPad and Mac.
final class ChatFolderBar: UIView {

    enum Layout {
        case tabs
        case sidebar
    }

    struct Item: Equatable {
        let folder: ChatFolder
        let unreadCount: Int
        var extras = ChatFolderExtras()
    }

    static let sidebarWidth: CGFloat = 80

    var onSelect: ((ChatFolder) -> Void)?
    var menuProvider: ((ChatFolder) -> UIMenu?)?
    var onEditFolders: (() -> Void)?

    private(set) var layout: Layout
    private(set) var items: [Item] = []
    private(set) var selectedFolderId: Data?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(layout: Layout) {
        self.layout = layout
        super.init(frame: .zero)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)
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
        ])
        applyLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLayout(_ layout: Layout) {
        guard layout != self.layout else {
            return
        }
        self.layout = layout
        applyLayout()
        reloadButtons()
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
        switch layout {
        case .tabs:
            return CGSize(width: UIView.noIntrinsicMetric, height: 52)
        case .sidebar:
            return CGSize(width: Self.sidebarWidth, height: UIView.noIntrinsicMetric)
        }
    }

    // MARK: - Private

    private var stackConstraints: [NSLayoutConstraint] = []

    private func applyLayout() {
        NSLayoutConstraint.deactivate(stackConstraints)
        switch layout {
        case .tabs:
            stackView.axis = .horizontal
            stackView.spacing = 8
            stackView.alignment = .center
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            scrollView.alwaysBounceHorizontal = true
            scrollView.alwaysBounceVertical = false
            stackConstraints = [stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)]
        case .sidebar:
            stackView.axis = .vertical
            stackView.spacing = 6
            stackView.alignment = .fill
            stackView.isLayoutMarginsRelativeArrangement = true
            // The trailing margin keeps the folders apart from the chats.
            stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 8)
            scrollView.alwaysBounceHorizontal = false
            scrollView.alwaysBounceVertical = true
            stackConstraints = [stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)]
        }
        NSLayoutConstraint.activate(stackConstraints)
        invalidateIntrinsicContentSize()
    }

    /// Keeps the right-click menus alive; interactions hold their delegates weakly.
    private var rightClickMenus: [RightClickMenu] = []

    private final class RightClickMenu: NSObject, UIContextMenuInteractionDelegate {
        let menu: UIMenu

        init(menu: UIMenu) {
            self.menu = menu
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint,
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(actionProvider: { [menu] _ in menu })
        }
    }

    private func reloadButtons() {
        rightClickMenus = []
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            stackView.addArrangedSubview(button(for: item))
        }
        stackView.addArrangedSubview(editButton())
    }

    private func button(for item: Item) -> UIButton {
        let isSelected = item.folder.id == selectedFolderId
        var configuration: UIButton.Configuration = isSelected ? .filled() : .plain()
        configuration.baseBackgroundColor = .Signal.secondaryFill
        configuration.baseForegroundColor = isSelected ? .Signal.label : .Signal.secondaryLabel
        configuration.cornerStyle = .capsule
        if let color = item.extras.color {
            configuration.baseBackgroundColor = Self.uiColor(for: color).withAlphaComponent(0.22)
            configuration.baseForegroundColor = isSelected ? .Signal.label : Self.uiColor(for: color)
        }

        let title = Self.title(for: item.folder)
        let emojiPrefix = (layout == .tabs ? item.extras.emoji.map { $0 + " " } : nil) ?? ""
        var attributedTitle = AttributedString(emojiPrefix + title)
        attributedTitle.font = layout == .tabs
            ? UIFont.dynamicTypeSubheadlineClamped.semibold()
            : UIFont.dynamicTypeCaption1Clamped.medium()
        if item.unreadCount > 0 {
            var count = AttributedString(layout == .tabs ? "  \(item.unreadCount)" : "\n\(item.unreadCount)")
            count.font = (layout == .tabs ? UIFont.dynamicTypeCaption1Clamped : UIFont.dynamicTypeCaption2Clamped).semibold()
            count.foregroundColor = UIColor.Signal.accent
            attributedTitle += count
        }
        configuration.attributedTitle = attributedTitle

        switch layout {
        case .tabs:
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        case .sidebar:
            if let emoji = item.extras.emoji {
                configuration.image = Self.image(emoji: emoji)
            } else {
                configuration.image = UIImage(systemName: item.folder.kind == .allChats ? "bubble.left.and.bubble.right" : "folder")
            }
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            configuration.imagePlacement = .top
            configuration.imagePadding = 3
            configuration.titleAlignment = .center
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.cornerStyle = .medium
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 2, bottom: 7, trailing: 2)
        }

        let folder = item.folder
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onSelect?(folder)
        })
#if targetEnvironment(macCatalyst)
        // On the Mac, the folder menu opens with a right-click, not by
        // holding the button.
        if let menu = menuProvider?(folder) {
            let menuDelegate = RightClickMenu(menu: menu)
            rightClickMenus.append(menuDelegate)
            button.addInteraction(UIContextMenuInteraction(delegate: menuDelegate))
        }
#else
        button.menu = menuProvider?(folder)
#endif
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
        configuration.image = UIImage(systemName: "ellipsis.circle")
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
