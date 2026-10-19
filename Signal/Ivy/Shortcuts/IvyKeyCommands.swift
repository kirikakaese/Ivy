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

    /// Adds the commands to the Mac's menus.
    static func build(_ builder: UIMenuBuilder) {
        guard builder.system == .main else {
            return
        }
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
    }
}

extension ConversationSplitViewController {

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
