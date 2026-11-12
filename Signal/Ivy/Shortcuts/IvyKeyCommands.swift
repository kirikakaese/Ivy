//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Keyboard shortcuts for Ivy's sections and for new tasks and events. On
/// the Mac they are menu commands (View and File menus), next to Show or
/// Hide Sidebar; on the iPad, key commands of the main screen.
@MainActor
enum IvyKeyCommands {

    static func commands() -> [UIKeyCommand] {
        sectionCommands() + newItemCommands() + zoomCommands() + [lockCommand()] + findCommands()
    }

    /// ⌘1 to ⌘4, in the order of the sections.
    static func sectionCommands() -> [UIKeyCommand] {
        let sections: [(IvySection, Selector)] = [
            (.home, #selector(ConversationSplitViewController.ivyShowHome)),
            (.chats, #selector(ConversationSplitViewController.ivyShowChats)),
            (.calendar, #selector(ConversationSplitViewController.ivyShowCalendar)),
            (.calls, #selector(ConversationSplitViewController.ivyShowCalls)),
        ]
        return sections.enumerated().map { index, entry in
            let title = IvyHomeSettingsViewController.title(for: entry.0)
            return UIKeyCommand(
                title: title,
                action: entry.1,
                input: "\(index + 1)",
                modifierFlags: .command,
                discoverabilityTitle: title,
            )
        }
    }

    /// ⌥⌘T for a new task, ⌥⌘E for a new event.
    static func newItemCommands() -> [UIKeyCommand] {
        let newTask = IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task.")
        let newEvent = IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event.")
        return [
            UIKeyCommand(
                title: newTask,
                action: #selector(ConversationSplitViewController.ivyNewTask),
                input: "t",
                modifierFlags: [.command, .alternate],
                discoverabilityTitle: newTask,
            ),
            UIKeyCommand(
                title: newEvent,
                action: #selector(ConversationSplitViewController.ivyNewEvent),
                input: "e",
                modifierFlags: [.command, .alternate],
                discoverabilityTitle: newEvent,
            ),
        ]
    }

    /// ⇧⌘F searches everything, ⇧⌘L opens the library.
    static func findCommands() -> [UIKeyCommand] {
        [
            UIKeyCommand(
                title: IvyFind.searchTitle,
                action: #selector(ConversationSplitViewController.ivySearchEverything),
                input: "f",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: IvyFind.searchTitle,
            ),
            UIKeyCommand(
                title: IvyFind.libraryTitle,
                action: #selector(ConversationSplitViewController.ivyShowLibrary),
                input: "l",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: IvyFind.libraryTitle,
            ),
        ]
    }

    /// ⌃⌘L locks Ivy right away (see IvyPrivacy).
    static func lockCommand() -> UIKeyCommand {
        UIKeyCommand(
            title: IvyPrivacy.lockTitle,
            action: #selector(ConversationSplitViewController.ivyLockNow),
            input: "l",
            modifierFlags: [.control, .command],
            discoverabilityTitle: IvyPrivacy.lockTitle,
        )
    }

    /// ⌘+, ⌘− and ⌘0 for the text size (see IvyZoom).
    static func zoomCommands() -> [UIKeyCommand] {
        [
            UIKeyCommand(
                title: IvyLocalizedString("ZOOM_IN", comment: "Menu command that makes the app's text bigger."),
                action: #selector(ConversationSplitViewController.ivyZoomIn),
                input: "+",
                modifierFlags: .command,
            ),
            UIKeyCommand(
                title: IvyLocalizedString("ZOOM_OUT", comment: "Menu command that makes the app's text smaller."),
                action: #selector(ConversationSplitViewController.ivyZoomOut),
                input: "-",
                modifierFlags: .command,
            ),
            UIKeyCommand(
                title: IvyLocalizedString("ZOOM_RESET", comment: "Menu command that sets the app's text back to its normal size."),
                action: #selector(ConversationSplitViewController.ivyZoomReset),
                input: "0",
                modifierFlags: .command,
            ),
        ].map {
            $0.discoverabilityTitle = $0.title
            return $0
        }
    }

#if targetEnvironment(macCatalyst)
    /// The commands of the Chat menu that need an open chat. They are
    /// greyed out without one.
    static let chatActions: [Selector] = [
        #selector(ConversationSplitViewController.openConversationSettings),
        #selector(ConversationSplitViewController.openAllMedia),
        #selector(ConversationSplitViewController.ivySearchInSelectedChat),
        #selector(ConversationSplitViewController.openAttachmentKeyboard),
        #selector(ConversationSplitViewController.openStickerKeyboard),
        #selector(ConversationSplitViewController.openGifSearch),
        #selector(ConversationSplitViewController.focusInputToolbar),
        #selector(ConversationSplitViewController.ivyOpenSelectedChatInWindow),
        #selector(ConversationSplitViewController.ivyMarkSelectedChatUnread),
        #selector(ConversationSplitViewController.archiveSelectedConversation),
    ]

    /// The split view's own key commands whose shortcut a menu item now
    /// carries. It leaves these out, so a shortcut isn't defined twice.
    static let menuActions: [Selector] = [
        #selector(ConversationSplitViewController.openConversationSettings),
        #selector(ConversationSplitViewController.openAllMedia),
        #selector(ConversationSplitViewController.openStickerKeyboard),
        #selector(ConversationSplitViewController.focusInputToolbar),
        #selector(ConversationSplitViewController.archiveSelectedConversation),
        #selector(ConversationSplitViewController.selectNextConversation(_:)),
        #selector(ConversationSplitViewController.selectPreviousConversation),
        #selector(ConversationSplitViewController.showNewConversationView),
        #selector(ConversationSplitViewController.showAppSettings),
    ]

    /// The Chat menu, Settings in the app menu, and New Message and New
    /// Group at the top of File. The chat's shortcuts existed, but no menu
    /// showed them.
    private static func buildChatMenus(_ builder: UIMenuBuilder) {
        func command(_ title: String, _ action: Selector, _ input: String, _ modifiers: UIKeyModifierFlags) -> UIKeyCommand {
            UIKeyCommand(title: title, action: action, input: input, modifierFlags: modifiers)
        }
        /// A command whose shortcut the system's own menus also use (Find
        /// Next, Underline). It has no shortcut in the menu; the chat's own
        /// key command still carries it.
        func plain(_ title: String, _ action: Selector) -> UICommand {
            UICommand(title: title, action: action)
        }
        func group(_ name: String, _ children: [UIMenuElement]) -> UIMenu {
            UIMenu(identifier: UIMenu.Identifier("ivy.chat." + name), options: .displayInline, children: children)
        }
        let look = group("look", [
            command(IvyLocalizedString("MENU_CHAT_INFO", comment: "Mac menu command that opens the open chat's info."), #selector(ConversationSplitViewController.openConversationSettings), "i", [.command, .shift]),
            command(IvyLocalizedString("MENU_CHAT_ALL_MEDIA", comment: "Mac menu command that opens the open chat's media."), #selector(ConversationSplitViewController.openAllMedia), "m", [.command, .shift]),
            plain(IvyLocalizedString("MENU_CHAT_SEARCH", comment: "Mac menu command that searches the messages of the open chat."), #selector(ConversationSplitViewController.ivySearchInSelectedChat)),
        ])
        let write = group("write", [
            plain(IvyLocalizedString("MENU_CHAT_ATTACH", comment: "Mac menu command that opens the attachment picker of the open chat."), #selector(ConversationSplitViewController.openAttachmentKeyboard)),
            command(IvyLocalizedString("MENU_CHAT_STICKERS", comment: "Mac menu command that opens the sticker picker of the open chat."), #selector(ConversationSplitViewController.openStickerKeyboard), "s", [.command, .shift]),
            plain(IvyLocalizedString("MENU_CHAT_GIF", comment: "Mac menu command that opens the GIF search of the open chat."), #selector(ConversationSplitViewController.openGifSearch)),
            command(IvyLocalizedString("MENU_CHAT_WRITE", comment: "Mac menu command that puts the cursor in the open chat's message field."), #selector(ConversationSplitViewController.focusInputToolbar), "t", [.command, .shift]),
        ])
        let manage = group("manage", [
            command(IvyChatWindows.openInNewWindowTitle, #selector(ConversationSplitViewController.ivyOpenSelectedChatInWindow), "o", [.command, .alternate]),
            command(IvyLocalizedString("MENU_CHAT_MARK_UNREAD", comment: "Mac menu command that marks the open chat as unread and closes it."), #selector(ConversationSplitViewController.ivyMarkSelectedChatUnread), "u", [.command, .control]),
            command(IvyLocalizedString("MENU_CHAT_ARCHIVE", comment: "Mac menu command that archives the open chat."), #selector(ConversationSplitViewController.archiveSelectedConversation), "a", [.command, .shift]),
        ])
        let move = group("move", [
            command(IvyLocalizedString("MENU_CHAT_NEXT", comment: "Mac menu command that opens the next chat in the list."), #selector(ConversationSplitViewController.selectNextConversation(_:)), UIKeyCommand.inputDownArrow, .alternate),
            command(IvyLocalizedString("MENU_CHAT_PREVIOUS", comment: "Mac menu command that opens the previous chat in the list."), #selector(ConversationSplitViewController.selectPreviousConversation), UIKeyCommand.inputUpArrow, .alternate),
        ])
        builder.insertSibling(
            UIMenu(
                title: IvyLocalizedString("MENU_CHAT", comment: "Title of the Mac menu with the commands for the open chat."),
                identifier: UIMenu.Identifier("ivy.chat"),
                children: [look, write, manage, move],
            ),
            beforeMenu: .window,
        )
        builder.insertChild(
            UIMenu(identifier: UIMenu.Identifier("ivy.newchat"), options: .displayInline, children: [
                command(IvyLocalizedString("MENU_NEW_MESSAGE", comment: "Mac File menu command that starts a new message."), #selector(ConversationSplitViewController.ivyNewMessageFromAnySection), "n", .command),
                plain(IvyLocalizedString("MENU_NEW_GROUP", comment: "Mac File menu command that starts a new group."), #selector(ConversationSplitViewController.ivyNewGroupFromAnySection)),
            ]),
            atStartOfMenu: .file,
        )
        // Settings in the app menu opens Ivy's settings. The system's own
        // item, where there is one, opens an empty window of system
        // settings, so Ivy's takes its place; otherwise it goes after About,
        // with Check for Updates put between the two below.
        let settings = UIMenu(identifier: UIMenu.Identifier("ivy.settings"), options: .displayInline, children: [
            command(IvyLocalizedString("MENU_SETTINGS", comment: "Mac app menu command that opens Settings."), #selector(ConversationSplitViewController.ivyShowSettingsFromAnySection), ",", .command),
        ])
        if builder.menu(for: .preferences) != nil {
            builder.replace(menu: .preferences, with: settings)
        } else {
            builder.insertSibling(settings, afterMenu: .about)
        }
    }
#endif

    /// Adds the commands to the Mac's menus.
    static func build(_ builder: UIMenuBuilder) {
        guard builder.system == .main else {
            return
        }
        // Chats open in their own windows; there is one main window.
        builder.remove(menu: .newScene)
        let toggleSidebar = UIKeyCommand(
            title: IvyLocalizedString("SIDEBAR_HIDE", comment: "Menu command that hides the sidebar."),
            action: #selector(ConversationSplitViewController.ivyToggleSidebar),
            input: "s",
            modifierFlags: [.control, .command],
        )
        builder.insertChild(
            UIMenu(identifier: UIMenu.Identifier("ivy.sections"), options: .displayInline, children: [toggleSidebar] + sectionCommands()),
            atStartOfMenu: .view,
        )
        builder.insertChild(
            UIMenu(identifier: UIMenu.Identifier("ivy.new"), options: .displayInline, children: newItemCommands() + [lockCommand()]),
            atEndOfMenu: .file,
        )
        builder.insertSibling(
            UIMenu(identifier: UIMenu.Identifier("ivy.zoom"), options: .displayInline, children: zoomCommands()),
            afterMenu: UIMenu.Identifier("ivy.sections"),
        )
        builder.insertSibling(
            UIMenu(identifier: UIMenu.Identifier("ivy.find"), options: .displayInline, children: findCommands()),
            afterMenu: UIMenu.Identifier("ivy.zoom"),
        )
        #if targetEnvironment(macCatalyst)
        buildChatMenus(builder)
        if IvyMacBetaUpdater.isAvailable {
            let checkForUpdates = UICommand(
                title: IvyLocalizedString("MAC_BETA_CHECK_FOR_UPDATES", comment: "Mac menu command that looks for a newer Mac beta."),
                action: #selector(ConversationSplitViewController.ivyCheckForUpdates),
            )
            builder.insertSibling(
                UIMenu(identifier: UIMenu.Identifier("ivy.updates"), options: .displayInline, children: [checkForUpdates]),
                afterMenu: .about,
            )
        }
        #endif
        // There's no shake on the Mac, so Report a Problem is in the Help menu.
        let reportProblem = UICommand(
            title: IvyLocalizedString("REPORT_PROBLEM_MENU", comment: "Mac Help menu command that opens Report a Problem."),
            action: #selector(ConversationSplitViewController.ivyReportProblem),
        )
        builder.insertChild(
            UIMenu(identifier: UIMenu.Identifier("ivy.help"), options: .displayInline, children: [reportProblem]),
            atStartOfMenu: .help,
        )
    }
}

extension ConversationSplitViewController {

    @objc
    func ivyCheckForUpdates() {
        #if targetEnvironment(macCatalyst)
        // Settings > Updates, which looks right away.
        IvyMacBetaUpdater.showUpdatesPage()
        Task { await IvyMacBetaUpdater.check(userInitiated: true, quietly: true) }
        #endif
    }

    @objc
    func ivyReportProblem() {
        IvyProblemReport.present(capturing: view.window)
    }

    @objc
    func ivyShowHome() {
        IvyLinkHandler.open(.home)
    }

    @objc
    func ivyShowChats() {
        IvyLinkHandler.open(.chats)
    }

    @objc
    func ivyShowCalendar() {
        IvyLinkHandler.open(.calendar)
    }

    @objc
    func ivyShowCalls() {
        IvyLinkHandler.open(.calls)
    }

    @objc
    func ivyNewTask() {
        IvyLinkHandler.open(.newTask)
    }

    @objc
    func ivyNewEvent() {
        IvyLinkHandler.open(.newEvent)
    }
}
