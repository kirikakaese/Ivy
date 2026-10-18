//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppKit

/// Ivy's menu bar extra on the Mac: the unread count, today's agenda, open
/// tasks and shortcuts for a new task or event.
///
/// The Mac app is built with Mac Catalyst and can't use AppKit itself, so it
/// loads this bundle and talks to it through Objective-C messages:
/// `installWithHandler:strings:` once, then `updateWithGlance:` with the
/// encoded `IvyGlance` whenever it changes. Choosing an item sends
/// `openIvyLink:` with the item's link to the handler.
@objc(IvyMenuBarPlugin)
final class IvyMenuBarPlugin: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private weak var handler: NSObject?
    private var strings = [String: String]()
    private var glance = IvyGlance.empty

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

    @objc
    private func openLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? URL else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        handler?.perform(NSSelectorFromString("openIvyLink:"), with: link.absoluteString as NSString)
    }
}
