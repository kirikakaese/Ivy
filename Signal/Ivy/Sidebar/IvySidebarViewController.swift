//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// What the sidebar shows besides the sections: the chat folders, which
/// folder is open, and the unread counts. The chat list and the tab bar
/// controller keep it up to date.
@MainActor
final class IvySidebarState {

    static let shared = IvySidebarState()

    init() {}

    static let didChange = Notification.Name("IvySidebarDidChange")

    /// The custom folders. "All Chats" is the Chats row.
    private(set) var folders: [ChatFolderBar.Item] = []
    private(set) var allChatsFolder: ChatFolder?
    /// Nil when all chats are shown.
    private(set) var selectedFolderId: Data?
    private(set) var unreadChatCount: UInt = 0
    private(set) var unreadCallsCount: UInt = 0

    func update(folders: [ChatFolderBar.Item], allChatsFolder: ChatFolder?, selectedFolderId: Data?) {
        guard folders != self.folders || allChatsFolder != self.allChatsFolder || selectedFolderId != self.selectedFolderId else {
            return
        }
        self.folders = folders
        self.allChatsFolder = allChatsFolder
        self.selectedFolderId = selectedFolderId
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func updateBadges(unreadChatCount: UInt, unreadCallsCount: UInt) {
        guard unreadChatCount != self.unreadChatCount || unreadCallsCount != self.unreadCallsCount else {
            return
        }
        self.unreadChatCount = unreadChatCount
        self.unreadCallsCount = unreadCallsCount
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// The selected section changed.
    func sectionDidChange() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// The sidebar on the Mac and on a wide iPad: the sections, then the chat
/// folders. Built on the system's sidebar list, with Ivy's spacing, colors
/// and selection.
final class IvySidebarViewController: UIViewController, UICollectionViewDelegate {

    enum Section: Hashable {
        case sections
        case folders
    }

    enum Item: Hashable {
        case section(HomeTabBarController.Tabs)
        case foldersHeader
        case folder(Data)
        /// Shown instead of folders while there are none.
        case newFolder
    }

    /// Spacing and colors of the sidebar.
    enum Style {
        /// Between the sidebar's edges and the rows.
        static let sideInset: CGFloat = 10
        /// Inside a row, around its icon and title.
        static let rowMargins = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        static let iconWidth: CGFloat = 22
        static let iconToText: CGFloat = 10
        static let cornerRadius: CGFloat = 8

        static let background = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgbHex: 0x18181A) : UIColor(rgbHex: 0xF2F2F5)
        }
        static var selection: UIColor { UIColor.Signal.accent.withAlphaComponent(0.22) }
        static var highlight: UIColor { UIColor.Signal.secondaryFill }
    }

    private unowned let homeVC: HomeTabBarController
    private var state: IvySidebarState { .shared }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init(homeVC: HomeTabBarController) {
        self.homeVC = homeVC
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var chatList: ChatListViewController { homeVC.chatListViewController }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Style.background

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: Self.layout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.selectionFollowsFocus = true
        collectionView.showsVerticalScrollIndicator = false
        view.addSubview(collectionView)

        configureDataSource()
        reload(animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: IvySidebarState.didChange, object: nil)
    }

    @objc
    private func stateDidChange() {
        reload(animated: true)
    }

    // MARK: - Layout

    private static func layout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            configuration.headerMode = sectionIndex == 1 ? .firstItemInSection : .none
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            section.interGroupSpacing = 2
            section.contentInsets = NSDirectionalEdgeInsets(
                top: sectionIndex == 0 ? 16 : 22,
                leading: Style.sideInset,
                bottom: 8,
                trailing: Style.sideInset,
            )
            return section
        }
    }

    // MARK: - Cells

    static func symbolName(for tab: HomeTabBarController.Tabs) -> String {
        switch tab {
        case .home: return "house"
        case .chatList: return "bubble.left.and.bubble.right"
        case .calendar: return "calendar"
        case .calls: return "phone"
        case .stories: return "circle.dashed"
        }
    }

    /// A row's content: icon in a fixed column, so every title lines up.
    private static func rowContent(text: String, image: UIImage?, iconColor: UIColor = .Signal.accent) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.sidebarCell()
        content.text = text
        content.textProperties.font = .dynamicTypeBody
        content.textProperties.color = .Signal.label
        content.image = image
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        content.imageProperties.tintColor = iconColor
        content.imageProperties.reservedLayoutSize = CGSize(width: Style.iconWidth, height: 0)
        content.imageToTextPadding = Style.iconToText
        content.directionalLayoutMargins = Style.rowMargins
        return content
    }

    /// Rounded rows: Ivy's green when selected, a light fill under the
    /// pointer or finger.
    private static func applyBackground(to cell: UICollectionViewListCell) {
        cell.configurationUpdateHandler = { cell, state in
            var background = UIBackgroundConfiguration.listSidebarCell()
            background.cornerRadius = Style.cornerRadius
            if state.isSelected {
                background.backgroundColor = Style.selection
            } else if state.isHighlighted {
                background.backgroundColor = Style.highlight
            } else {
                background.backgroundColor = .clear
            }
            cell.backgroundConfiguration = background
        }
    }

    private static func badge(_ count: Int) -> [UICellAccessory] {
        guard count > 0 else {
            return []
        }
        return [.label(text: count.formatted(), options: .init(
            reservedLayoutWidth: .actual,
            tintColor: .Signal.secondaryLabel,
            font: .dynamicTypeFootnote,
        ))]
    }

    private func configureDataSource() {
        let sectionCell = UICollectionView.CellRegistration<UICollectionViewListCell, HomeTabBarController.Tabs> { [unowned self] cell, _, tab in
            cell.contentConfiguration = Self.rowContent(text: tab.ivyTitle, image: UIImage(systemName: Self.symbolName(for: tab)))
            let count: UInt
            switch tab {
            case .chatList: count = state.unreadChatCount
            case .calls: count = state.unreadCallsCount
            case .home, .calendar, .stories: count = 0
            }
            cell.accessories = Self.badge(Int(count))
            Self.applyBackground(to: cell)
        }

        let headerCell = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [unowned self] cell, _, _ in
            var content = UIListContentConfiguration.sidebarHeader()
            content.text = IvyLocalizedString("SIDEBAR_FOLDERS", comment: "Header of the chat folders in the sidebar.")
            content.textProperties.font = UIFont.dynamicTypeFootnote.semibold()
            content.textProperties.color = .Signal.secondaryLabel
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: Style.rowMargins.leading, bottom: 4, trailing: 4)
            cell.contentConfiguration = content
            cell.accessories = [.customView(configuration: .init(
                customView: newFolderButton(),
                placement: .trailing(displayed: .always),
                reservedLayoutWidth: .actual,
                maintainsFixedSize: true,
            ))]
            cell.backgroundConfiguration = .clear()
        }

        let folderCell = UICollectionView.CellRegistration<UICollectionViewListCell, ChatFolderBar.Item> { cell, _, item in
            let image: UIImage?
            var iconColor = UIColor.Signal.accent
            if let emoji = item.extras.emoji {
                image = ChatFolderBar.image(emoji: emoji)
            } else {
                image = UIImage(systemName: "folder")
                if let color = item.extras.color {
                    iconColor = ChatFolderBar.uiColor(for: color)
                }
            }
            cell.contentConfiguration = Self.rowContent(text: ChatFolderBar.title(for: item.folder), image: image, iconColor: iconColor)
            cell.accessories = Self.badge(item.unreadCount)
            Self.applyBackground(to: cell)
        }

        let newFolderCell = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, _ in
            var content = Self.rowContent(
                text: IvyLocalizedString("SIDEBAR_NEW_FOLDER", comment: "Button in the sidebar that makes a new chat folder."),
                image: UIImage(systemName: "plus"),
                iconColor: .Signal.secondaryLabel,
            )
            content.textProperties.color = .Signal.secondaryLabel
            cell.contentConfiguration = content
            cell.accessories = []
            Self.applyBackground(to: cell)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [unowned self] collectionView, indexPath, item in
            switch item {
            case .section(let tab):
                return collectionView.dequeueConfiguredReusableCell(using: sectionCell, for: indexPath, item: tab)
            case .foldersHeader:
                return collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: item)
            case .folder(let id):
                let folder = state.folders.first { $0.folder.id == id }
                    ?? ChatFolderBar.Item(folder: ChatFolder(id: id, name: ""), unreadCount: 0)
                return collectionView.dequeueConfiguredReusableCell(using: folderCell, for: indexPath, item: folder)
            case .newFolder:
                return collectionView.dequeueConfiguredReusableCell(using: newFolderCell, for: indexPath, item: item)
            }
        }
    }

    private func newFolderButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium))
        configuration.baseForegroundColor = .Signal.secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.showNewFolder()
        })
        button.accessibilityLabel = IvyLocalizedString("SIDEBAR_NEW_FOLDER", comment: "Button in the sidebar that makes a new chat folder.")
        button.toolTip = button.accessibilityLabel
        return button
    }

    // MARK: - Contents

    private func reload(animated: Bool) {
        if dataSource.snapshot().sectionIdentifiers.isEmpty {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.sections, .folders])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        var sections = NSDiffableDataSourceSectionSnapshot<Item>()
        sections.append(homeVC.ivyShownTabs.map { .section($0) })

        var folders = NSDiffableDataSourceSectionSnapshot<Item>()
        folders.append([.foldersHeader])
        let folderItems: [Item] = state.folders.map { .folder($0.folder.id) }
        folders.append(folderItems.isEmpty ? [.newFolder] : folderItems)

        dataSource.apply(sections, to: .sections, animatingDifferences: animated)
        dataSource.apply(folders, to: .folders, animatingDifferences: animated)
        // Counts and names live in the state, so rows that stayed are
        // updated too.
        var reconfigured = dataSource.snapshot()
        reconfigured.reconfigureItems(reconfigured.itemIdentifiers)
        dataSource.apply(reconfigured, animatingDifferences: false)

        updateSelection()
    }

    /// Highlights the open section, or the open folder in Chats.
    private func updateSelection() {
        let item: Item
        let tab = homeVC.selectedHomeTab
        if tab == .chatList, let folderId = state.selectedFolderId, state.folders.contains(where: { $0.folder.id == folderId }) {
            item = .folder(folderId)
        } else {
            item = .section(tab)
        }
        guard let indexPath = dataSource.indexPath(for: item) else {
            return
        }
        if collectionView.indexPathsForSelectedItems != [indexPath] {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .foldersHeader
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .section(let tab):
            homeVC.selectedHomeTab = tab
            if tab == .chatList, let allChats = state.allChatsFolder {
                chatList.ivySelectChatFolder(allChats)
            }
        case .folder(let id):
            guard let item = state.folders.first(where: { $0.folder.id == id }) else {
                return
            }
            homeVC.selectedHomeTab = .chatList
            chatList.ivySelectChatFolder(item.folder)
        case .newFolder:
            showNewFolder()
        case .foldersHeader, nil:
            break
        }
        updateSelection()
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let menu: UIMenu?
        switch dataSource.itemIdentifier(for: indexPath) {
        case .folder(let id):
            menu = state.folders.first { $0.folder.id == id }.map { chatList.ivyMenu(for: $0.folder) }
        case .section(.chatList):
            menu = state.allChatsFolder.map { chatList.ivyMenu(for: $0) }
        case .foldersHeader, .newFolder:
            menu = UIMenu(children: [
                UIAction(
                    title: IvyLocalizedString("SIDEBAR_NEW_FOLDER", comment: "Button in the sidebar that makes a new chat folder."),
                    image: UIImage(systemName: "folder.badge.plus"),
                ) { [weak self] _ in
                    self?.showNewFolder()
                },
                UIAction(
                    title: IvyLocalizedString("CHAT_FOLDERS_EDIT", comment: "Button that opens the chat folder settings."),
                    image: Theme.iconImage(.contextMenuSettings),
                ) { [weak self] _ in
                    self?.chatList.ivyShowChatFolderSettings()
                },
            ])
        case .section, nil:
            menu = nil
        }
        guard let menu else {
            return nil
        }
        return UIContextMenuConfiguration(actionProvider: { _ in menu })
    }

    // MARK: - Actions

    private func showNewFolder() {
        let editor = ChatFolderEditorViewController(folder: nil)
        presentFormSheet(OWSNavigationController(rootViewController: editor), animated: true)
    }
}
