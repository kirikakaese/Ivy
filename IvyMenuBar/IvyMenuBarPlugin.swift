//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppKit
import Carbon.HIToolbox

/// Ivy's menu bar extra on the Mac: the unread count, the latest chats with a
/// quick reply, today's agenda, open tasks and shortcuts for a new task or
/// event. It also holds the global hotkey.
///
/// The Mac app is built with Mac Catalyst and can't use AppKit itself, so it
/// loads this bundle and talks to it through Objective-C messages:
/// `installWithHandler:strings:` once, then `updateWithGlance:` with the
/// encoded `IvyGlance` whenever it changes. Choosing an item sends
/// `openIvyLink:` with the item's link to the handler; the Mac's screen
/// locking or sleeping sends `ivyScreenDidLock`. `updateWithMessages:` gives
/// the latest chats; a quick reply sends `sendQuickReply:toThread:` and
/// opening a chat sends `openChatThread:`.
/// `setHotKeyWithKeyCode:modifiers:` sets the global hotkey (key code 0
/// removes it); pressing it sends `ivyHotKeyPressed`.
@objc(IvyMenuBarPlugin)
final class IvyMenuBarPlugin: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private weak var handler: NSObject?
    private var strings = [String: String]()
    private var glance = IvyGlance.empty
    private var quickChats = QuickChats(isLocked: false, chats: [])
    private var replyPanel: QuickReplyPanel?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    /// The latest chats, sent by the app. Never written to disk.
    struct QuickChats: Codable {
        var isLocked: Bool
        var chats: [QuickChat]
    }

    struct QuickChat: Codable {
        var threadId: String
        var name: String
        var snippet: String
        var isUnread: Bool
    }

    @objc(installWithHandler:strings:)
    func install(handler: NSObject, strings: NSDictionary) {
        self.handler = handler
        self.strings = strings as? [String: String] ?? [:]
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Ivy")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateButton()

        // Ivy locks with the Mac (when Screen Lock is on).
        let lock: (Notification) -> Void = { [weak self] _ in
            _ = self?.handler?.perform(NSSelectorFromString("ivyScreenDidLock"))
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: lock)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: lock)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: lock)
    }

    @objc(updateWithGlance:)
    func update(glanceData: NSData) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let glance = try? decoder.decode(IvyGlance.self, from: glanceData as Data) else {
            return
        }
        self.glance = glance
        updateButton()
    }

    @objc(updateWithMessages:)
    func update(messagesData: NSData) {
        guard let chats = try? JSONDecoder().decode(QuickChats.self, from: messagesData as Data) else {
            return
        }
        quickChats = chats
        if chats.isLocked {
            replyPanel?.close()
        }
    }

    private func updateButton() {
        statusItem?.button?.title = glance.unreadCount > 0 ? " \(glance.unreadCount)" : ""
    }

    // MARK: - Menu

    /// Built when it opens, so finished items are gone.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()

        if glance.unreadCount > 0, let format = strings["unreadFormat"] {
            menu.addItem(linkItem(String(format: format, glance.unreadCount), link: IvyLink.chats.url, image: "bubble.left.and.bubble.right"))
            menu.addItem(.separator())
        }

        if !quickChats.chats.isEmpty || quickChats.isLocked {
            menu.addItem(header(strings["messages"] ?? ""))
            if quickChats.isLocked {
                menu.addItem(disabledItem(strings["locked"] ?? ""))
            }
            for chat in quickChats.chats.prefix(5) {
                let item = NSMenuItem(title: "", action: #selector(openQuickReply(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = chat.threadId
                item.image = NSImage(systemSymbolName: chat.isUnread ? "circle.fill" : "bubble.left", accessibilityDescription: nil)
                let title = NSMutableAttributedString(
                    string: chat.name,
                    attributes: [.font: chat.isUnread ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize) : NSFont.menuFont(ofSize: 0)],
                )
                title.append(NSAttributedString(
                    string: "  " + String(chat.snippet.prefix(60)),
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.menuFont(ofSize: 0)],
                ))
                item.attributedTitle = title
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(header(strings["today"] ?? ""))
        let today = glance.todayRemaining(at: now)
        if today.isEmpty {
            menu.addItem(disabledItem(strings["nothingToday"] ?? ""))
        }
        for item in today {
            menu.addItem(linkItem(itemTitle(item), link: item.link, image: icon(for: item)))
        }

        menu.addItem(.separator())
        menu.addItem(header(strings["tasks"] ?? ""))
        if glance.tasks.isEmpty {
            menu.addItem(disabledItem(strings["noOpenTasks"] ?? ""))
        }
        for task in glance.tasks.prefix(5) {
            menu.addItem(linkItem(itemTitle(task), link: task.link, image: "circle"))
        }

        menu.addItem(.separator())
        menu.addItem(linkItem(strings["newTask"] ?? "", link: IvyLink.newTask.url, image: "checklist"))
        menu.addItem(linkItem(strings["newEvent"] ?? "", link: IvyLink.newEvent.url, image: "calendar.badge.plus"))
        menu.addItem(linkItem(strings["open"] ?? "Ivy", link: IvyLink.home.url, image: "leaf"))
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        return disabledItem(title)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func linkItem(_ title: String, link: URL, image: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = link
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        return item
    }

    private func itemTitle(_ item: IvyGlance.Item) -> String {
        guard let start = item.start else {
            return item.title
        }
        let time: String
        if item.isAllDay {
            time = Calendar.current.isDateInToday(start) ? (strings["allDay"] ?? "") : start.formatted(.dateTime.day().month(.abbreviated))
        } else if Calendar.current.isDateInToday(start) {
            time = start.formatted(date: .omitted, time: .shortened)
        } else {
            time = start.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        }
        return "\(time)  \(item.title)"
    }

    private func icon(for item: IvyGlance.Item) -> String {
        switch item.kind {
        case .event: return "calendar"
        case .task: return "circle"
        case .reminder: return "bell"
        }
    }

    // MARK: - Quick reply

    @objc
    private func openQuickReply(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? String, let chat = quickChats.chats.first(where: { $0.threadId == threadId }) else {
            return
        }
        replyPanel?.close()
        let panel = QuickReplyPanel(chat: chat, strings: strings) { [weak self] text in
            _ = self?.handler?.perform(NSSelectorFromString("sendQuickReply:toThread:"), with: text as NSString, with: threadId as NSString)
        } onOpen: { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            _ = self?.handler?.perform(NSSelectorFromString("openChatThread:"), with: threadId as NSString)
        }
        replyPanel = panel
        panel.show()
    }

    // MARK: - Hotkey

    private static weak var current: IvyMenuBarPlugin?

    @objc(setHotKeyWithKeyCode:modifiers:)
    func setHotKey(keyCode: NSNumber, modifiers: NSNumber) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard keyCode.uint32Value != 0 else {
            return
        }
        Self.current = self
        if hotKeyHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    _ = IvyMenuBarPlugin.current?.handler?.perform(NSSelectorFromString("ivyHotKeyPressed"))
                }
                return noErr
            }, 1, &eventType, nil, &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: OSType(0x49_56_59_31), id: 1)
        RegisterEventHotKey(keyCode.uint32Value, modifiers.uint32Value, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    @objc
    private func openLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? URL else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        handler?.perform(NSSelectorFromString("openIvyLink:"), with: link.absoluteString as NSString)
    }
}

/// A small window to answer a chat without opening Ivy.
private final class QuickReplyPanel: NSPanel, NSTextFieldDelegate {

    private let field = NSTextField()
    private let onSend: (String) -> Void

    init(chat: IvyMenuBarPlugin.QuickChat, strings: [String: String], onSend: @escaping (String) -> Void, onOpen: @escaping () -> Void) {
        self.onSend = onSend
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        title = chat.name
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let snippet = NSTextField(wrappingLabelWithString: chat.snippet)
        snippet.textColor = .secondaryLabelColor
        snippet.maximumNumberOfLines = 3
        field.placeholderString = strings["replyPlaceholder"]
        field.delegate = self
        let send = NSButton(title: strings["send"] ?? "Send", target: self, action: #selector(sendTapped))
        send.keyEquivalent = "\r"
        send.bezelColor = .controlAccentColor
        let open = NSButton(title: strings["openChat"] ?? "Open", target: nil, action: nil)
        open.bezelStyle = .rounded
        let openAction = onOpen
        open.target = self
        open.action = #selector(openTapped)
        self.onOpen = openAction
        let buttons = NSStackView(views: [open, NSView(), send])
        let stack = NSStackView(views: [snippet, field, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        contentView = stack
    }

    private var onOpen: (() -> Void)?

    func show() {
        center()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    override var canBecomeKey: Bool { true }

    @objc
    private func sendTapped() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        onSend(text)
        close()
    }

    @objc
    private func openTapped() {
        onOpen?()
        close()
    }
}
