//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Whether the chat list shows its folders and a search button at the
/// bottom, above the tab bar, in thumb reach. Off by default; chosen in
/// Settings > Chats and kept on this device. Not used next to the sidebar.
enum IvyChatListLayout {
    static let searchAtBottomKey = "IvyChatListSearchAtBottom"

    static func searchAtBottom(defaults: UserDefaults = .standard, appliesHere: Bool = IvyHand.appliesHere) -> Bool {
        appliesHere && defaults.bool(forKey: searchAtBottomKey)
    }

    static func setSearchAtBottom(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: searchAtBottomKey)
    }

    static let didChange = Notification.Name("IvyChatListLayoutDidChange")
}

/// The bar at the bottom of the chat list: the folder chips, if any, and a
/// search button that opens the chat list's search.
final class IvyChatListBottomBar: UIView {

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let stack = UIStackView()
    private let searchButton = UIButton(type: .system)
    private(set) var folderBar: ChatFolderBar?
    var onSearch: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        background.layer.cornerRadius = 24
        background.layer.cornerCurve = .continuous
        background.clipsToBounds = true
        addSubview(background)
        background.autoPinEdgesToSuperviewEdges()

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .Signal.secondaryFill
        config.baseForegroundColor = .Signal.secondaryLabel
        config.image = UIImage(systemName: "magnifyingglass")
        config.imagePadding = 8
        config.title = CommonStrings.searchPlaceholder
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        searchButton.configuration = config
        searchButton.contentHorizontalAlignment = .leading
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .primaryActionTriggered)

        stack.axis = .vertical
        stack.spacing = 2
        stack.addArrangedSubview(searchButton)
        addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 6, leading: 10, bottom: 10, trailing: 10))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Puts the folder chips above the search button, or removes them.
    func setFolderBar(_ bar: ChatFolderBar?) {
        guard bar !== folderBar else { return }
        folderBar?.removeFromSuperview()
        folderBar = bar
        if let bar {
            bar.removeFromSuperview()
            bar.translatesAutoresizingMaskIntoConstraints = true
            bar.autoresizingMask = []
            stack.insertArrangedSubview(bar, at: 0)
            if bar.constraints.allSatisfy({ $0.firstAttribute != .height }) {
                bar.autoSetDimension(.height, toSize: bar.intrinsicContentSize.height)
            }
        }
    }
}

extension ChatListViewController {

    private static var ivyBottomBarKey: UInt8 = 0
    private static var ivyBottomInsetKey: UInt8 = 0

    var ivyBottomBar: IvyChatListBottomBar? {
        get { objc_getAssociatedObject(self, &Self.ivyBottomBarKey) as? IvyChatListBottomBar }
        set { objc_setAssociatedObject(self, &Self.ivyBottomBarKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// The bottom inset the bar added to the chat list, to take back later.
    private var ivyBottomInset: CGFloat {
        get { objc_getAssociatedObject(self, &Self.ivyBottomInsetKey) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &Self.ivyBottomInsetKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Shows the bottom bar with the given folder chips, or none.
    func ivyShowBottomBar(folderBar: ChatFolderBar?) {
        let bar: IvyChatListBottomBar
        if let existing = ivyBottomBar {
            bar = existing
        } else {
            bar = IvyChatListBottomBar()
            bar.onSearch = { [weak self] in
                guard let self else { return }
                viewState.searchController.isActive = true
                viewState.searchController.searchBar.becomeFirstResponder()
            }
            view.addSubview(bar)
            bar.autoPinEdge(toSuperviewSafeArea: .leading, withInset: 10)
            bar.autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 10)
            bar.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)
            ivyBottomBar = bar
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak bar] _ in
                UIView.animate(withDuration: 0.2) { bar?.alpha = 0 }
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak bar] _ in
                UIView.animate(withDuration: 0.2) { bar?.alpha = 1 }
            }
        }
        bar.setFolderBar(folderBar)
        view.bringSubviewToFront(bar)
        view.layoutIfNeeded()
        // The last chats scroll up above the bar.
        let inset = bar.frame.height + 8
        tableView.contentInset.bottom += inset - ivyBottomInset
        tableView.verticalScrollIndicatorInsets.bottom += inset - ivyBottomInset
        ivyBottomInset = inset
    }

    func ivyHideBottomBar() {
        guard let bar = ivyBottomBar else { return }
        bar.setFolderBar(nil)
        bar.removeFromSuperview()
        ivyBottomBar = nil
        tableView.contentInset.bottom -= ivyBottomInset
        tableView.verticalScrollIndicatorInsets.bottom -= ivyBottomInset
        ivyBottomInset = 0
    }
}

extension OWSTableViewController2 {

    /// "Chat List": search and folders at the bottom.
    func ivyAddChatListLayoutSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("CHAT_LIST_LAYOUT_TITLE", comment: "Header of the chat list layout setting.")
        section.footerTitle = IvyLocalizedString("CHAT_LIST_SEARCH_BOTTOM_FOOTER", comment: "Footer explaining the setting that moves search and folders to the bottom of the chat list.")
        section.add(.switch(
            withText: IvyLocalizedString("CHAT_LIST_SEARCH_BOTTOM", comment: "Switch that moves the chat list's search and folders to the bottom, above the tab bar."),
            isOn: { IvyChatListLayout.searchAtBottom() },
            actionBlock: { uiSwitch in
                IvyChatListLayout.setSearchAtBottom(uiSwitch.isOn)
                NotificationCenter.default.post(name: IvyChatListLayout.didChange, object: nil)
            },
        ))
        contents.add(section)
    }
}
