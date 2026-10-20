//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Shows Ivy's menu bar extra on the Mac through the AppKit plugin in
/// `IvyMenuBar/` (see `IvyMenuBarPlugin`). Does nothing on iPhone and iPad.
@MainActor
final class IvyMenuBar: NSObject {

    static let shared = IvyMenuBar()

    private var plugin: NSObject?
    private var didTryLoading = false

    func update(_ glance: IvyGlance) {
        #if targetEnvironment(macCatalyst)
        guard let plugin = loadPlugin(), let data = glance.encoded() else {
            return
        }
        plugin.perform(NSSelectorFromString("updateWithGlance:"), with: data as NSData)
        #endif
    }

    private func loadPlugin() -> NSObject? {
        if didTryLoading {
            return plugin
        }
        didTryLoading = true
        guard
            let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("IvyMenuBar.bundle"),
            let bundle = Bundle(url: url),
            bundle.load(),
            let pluginClass = bundle.principalClass as? NSObject.Type
        else {
            Logger.warn("Couldn't load the menu bar plugin")
            return nil
        }
        let plugin = pluginClass.init()
        plugin.perform(NSSelectorFromString("installWithHandler:strings:"), with: self, with: Self.strings as NSDictionary)
        self.plugin = plugin
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleMessagesUpdate), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleMessagesUpdate), name: IvyHiddenChats.hiddenChatsDidChange, object: nil)
        applyHotKey()
        scheduleMessagesUpdate()
        return plugin
    }

    private static var strings: [String: String] {
        [
            "today": IvyLocalizedString("WIDGET_TODAY_TITLE", comment: "Name of the widget with today's events, due tasks and reminders."),
            "nothingToday": IvyLocalizedString("HOME_NOTHING_TODAY", comment: "Shown on Home when there are no events or reminders today."),
            "tasks": IvyTaskUI.tasksTitle,
            "noOpenTasks": IvyLocalizedString("TASKS_EMPTY_TITLE", comment: "Title shown in the list of tasks when there are no open tasks."),
            "allDay": IvyLocalizedString("TASK_ALL_DAY", comment: "Switch that makes a task due on a day without a time."),
            "newTask": IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task."),
            "newEvent": IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event."),
            "open": IvyLocalizedString("MENU_BAR_OPEN", comment: "Menu bar item that brings Ivy's window to the front."),
            "unreadFormat": IvyLocalizedString("MENU_BAR_UNREAD_FORMAT", comment: "Menu bar item with the number of unread messages. Embeds {{ number of unread messages }}."),
            "messages": IvyLocalizedString("MENU_BAR_MESSAGES", comment: "Header of the latest chats in the Mac's menu bar extra."),
            "locked": IvyLocalizedString("MENU_BAR_LOCKED", comment: "Shown in the Mac's menu bar extra instead of chats while Ivy is locked."),
            "replyPlaceholder": IvyLocalizedString("MENU_BAR_REPLY_PLACEHOLDER", comment: "Placeholder of the quick reply field in the Mac's menu bar extra."),
            "send": IvyLocalizedString("MENU_BAR_SEND", comment: "Button that sends a quick reply from the Mac's menu bar extra."),
            "openChat": IvyLocalizedString("MENU_BAR_OPEN_CHAT", comment: "Button in the quick reply window that opens the chat in Ivy."),
        ]
    }

    /// Called by the plugin when the Mac's screen locks or goes to sleep.
    @objc
    func ivyScreenDidLock() {
        IvyPrivacy.lockIfEnabled()
        updateMessages()
    }

    // MARK: - Latest chats

    /// Chats shown at most.
    private static let maxChats = 5
    private var messagesUpdateScheduled = false

    @objc
    private func scheduleMessagesUpdate() {
        guard plugin != nil, !messagesUpdateScheduled else {
            return
        }
        messagesUpdateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.messagesUpdateScheduled = false
            self?.updateMessages()
        }
    }

    private var isLocked: Bool {
        ScreenLock.shared.isScreenLockEnabled() && AppEnvironment.shared.screenLockUI.ivyIsLocked
    }

    /// Tells the plugin the latest chats, without hidden or locked ones.
    /// Nothing while Ivy is locked.
    private func updateMessages() {
        #if targetEnvironment(macCatalyst)
        guard let plugin else {
            return
        }
        var chats = [[String: Any]]()
        if !isLocked {
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                var lookedAt = 0
                ThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                    guard chats.count < Self.maxChats, lookedAt < 30 else {
                        return
                    }
                    lookedAt += 1
                    guard
                        !(IvyHiddenChats.shared.isHidden(thread: thread) && !IvyHiddenChats.shared.isRevealed),
                        !IvyLockedChats.shared.isLocked(thread: thread),
                        IvyChatReference(thread: thread).map({ IvySnoozedChats.shared.snoozedUntil($0) == nil }) ?? true
                    else {
                        return
                    }
                    let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
                    guard let message = finder.mostRecentInteractionForInbox(forChatListSorting: false, transaction: tx) as? TSMessage else {
                        return
                    }
                    let text = message.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? IvyLocalizedString("MENU_BAR_ATTACHMENT", comment: "Stands for a message without text in the Mac's menu bar extra.")
                    chats.append([
                        "threadId": thread.uniqueId,
                        "name": SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx),
                        "snippet": (message is TSOutgoingMessage ? IvyLocalizedString("MENU_BAR_YOU_PREFIX", comment: "Before the user's own last message in the Mac's menu bar extra.") + " " : "") + text,
                        "isUnread": finder.unreadCount(transaction: tx) > 0,
                    ])
                }
            }
        }
        let payload: [String: Any] = ["isLocked": isLocked, "chats": chats]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        plugin.perform(NSSelectorFromString("updateWithMessages:"), with: data as NSData)
        #endif
    }

    /// Called by the plugin to answer a chat from the menu bar.
    @objc
    func sendQuickReply(_ text: NSString, toThread threadId: NSString) {
        guard !isLocked else {
            return
        }
        let body = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return
        }
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard let thread = databaseStorage.read(block: { tx in
            DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadId as String, tx: tx)
        }) else {
            return
        }
        ThreadUtil.enqueueMessage(body: MessageBody(text: body, ranges: .empty), thread: thread)
        databaseStorage.write { tx in
            thread.markAllAsRead(updateStorageService: true, transaction: tx)
        }
        scheduleMessagesUpdate()
    }

    /// Called by the plugin to open a chat in Ivy's window.
    @objc
    func openChatThread(_ threadId: NSString) {
        IvyChatWindows.activateMainWindow()
        SignalApp.shared.presentConversationForThread(threadUniqueId: threadId as String, animated: true)
    }

    // MARK: - Global hotkey

    /// Tells the plugin the chosen hotkey.
    func applyHotKey() {
        #if targetEnvironment(macCatalyst)
        guard let plugin else {
            return
        }
        let hotKey = IvyHotKey.current
        plugin.perform(
            NSSelectorFromString("setHotKeyWithKeyCode:modifiers:"),
            with: NSNumber(value: hotKey.keyCode),
            with: NSNumber(value: hotKey.modifiers),
        )
        #endif
    }

    /// Called by the plugin when the hotkey is pressed; Ivy is already in
    /// front.
    @objc
    func ivyHotKeyPressed() {
        IvyChatWindows.activateMainWindow()
        switch IvyHotKey.action {
        case .showIvy:
            break
        case .newMessage:
            SignalApp.shared.conversationSplitViewController?.showNewConversationView()
        }
    }

    /// Called by the plugin when the user chooses an item.
    @objc
    func openIvyLink(_ link: NSString) {
        guard let url = URL(string: link as String), let ivyLink = IvyLink(url: url) else {
            return
        }
        // Brings the window back if it was closed.
        IvyChatWindows.activateMainWindow()
        IvyLinkHandler.open(ivyLink)
    }
}

extension IvyMenuBar: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdateInteractions || databaseChanges.didUpdateThreads {
            scheduleMessagesUpdate()
        }
    }

    func databaseChangesDidUpdateExternally() {
        scheduleMessagesUpdate()
    }

    func databaseChangesDidReset() {
        scheduleMessagesUpdate()
    }
}

/// The Mac's system-wide shortcut for Ivy. Kept on this Mac.
enum IvyHotKey: String, CaseIterable {
    case off
    case optionCommandI
    case controlOptionSpace
    case controlCommandI

    enum Action: String, CaseIterable {
        case showIvy
        case newMessage
    }

    private static let key = "IvyHotKey"
    private static let actionKey = "IvyHotKeyAction"

    static var current: IvyHotKey {
        get { UserDefaults.standard.string(forKey: key).flatMap(IvyHotKey.init(rawValue:)) ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var action: Action {
        get { UserDefaults.standard.string(forKey: actionKey).flatMap(Action.init(rawValue:)) ?? .showIvy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: actionKey) }
    }

    // Carbon's virtual key codes and modifier flags.
    private static let keyI: UInt32 = 0x22
    private static let keySpace: UInt32 = 0x31
    private static let command: UInt32 = 0x0100
    private static let option: UInt32 = 0x0800
    private static let control: UInt32 = 0x1000

    var keyCode: UInt32 {
        switch self {
        case .off: return 0
        case .optionCommandI, .controlCommandI: return Self.keyI
        case .controlOptionSpace: return Self.keySpace
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .off: return 0
        case .optionCommandI: return Self.option | Self.command
        case .controlOptionSpace: return Self.control | Self.option
        case .controlCommandI: return Self.control | Self.command
        }
    }

    var title: String {
        switch self {
        case .off: return CommonStrings.switchOff
        case .optionCommandI: return "⌥⌘I"
        case .controlOptionSpace: return IvyLocalizedString("HOTKEY_CONTROL_OPTION_SPACE", comment: "The keyboard shortcut Control-Option-Space, written with the Mac's key symbols.")
        case .controlCommandI: return "⌃⌘I"
        }
    }
}
