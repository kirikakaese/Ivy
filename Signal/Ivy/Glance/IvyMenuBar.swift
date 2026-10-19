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
        ]
    }

    /// Called by the plugin when the Mac's screen locks or goes to sleep.
    @objc
    func ivyScreenDidLock() {
        IvyPrivacy.lockIfEnabled()
    }

    /// Called by the plugin when the user chooses an item.
    @objc
    func openIvyLink(_ link: NSString) {
        guard let url = URL(string: link as String), let ivyLink = IvyLink(url: url) else {
            return
        }
        // Brings the window back if it was closed.
        if let session = UIApplication.shared.openSessions.first {
            UIApplication.shared.requestSceneSessionActivation(session, userActivity: nil, options: nil)
        }
        IvyLinkHandler.open(ivyLink)
    }
}
