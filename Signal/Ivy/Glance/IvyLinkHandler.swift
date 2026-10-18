//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Opens the place in Ivy that a widget, the menu bar or a shortcut links to.
@MainActor
enum IvyLinkHandler {

    static func open(_ link: IvyLink) {
        guard let split = SignalApp.shared.conversationSplitViewController else {
            Logger.warn("No window for an Ivy link")
            return
        }
        var presenter: UIViewController = split
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        switch link {
        case .home:
            split.homeVC.selectedHomeTab = .home
        case .chats:
            split.homeVC.selectedHomeTab = .chatList
        case .calendar:
            split.homeVC.selectedHomeTab = .calendar
        case .calls:
            split.homeVC.selectedHomeTab = .calls
        case .tasks:
            presenter.ivyPresentTasks()
        case .newTask:
            presenter.ivyPresentTaskEditor(IvyTask(title: ""), isNew: true)
        case .newEvent:
            presenter.ivyPresentEventEditor(newEvent(), isNew: true)
        case .task(let id):
            if let task = IvyTaskManager.shared.task(id: id) {
                presenter.ivyPresentTaskEditor(task, isNew: false)
            } else {
                presenter.ivyPresentTasks()
            }
        case .event(let id):
            if let event = IvyEventManager.shared.event(id: id) {
                presenter.ivyPresentEventEditor(event, isNew: false)
            } else {
                split.homeVC.selectedHomeTab = .calendar
            }
        }
    }

    /// A one-hour event at the next full hour.
    static func newEvent(now: Date = Date(), calendar: Calendar = .current) -> IvyEvent {
        let start = calendar.dateInterval(of: .hour, for: now)?.end ?? now
        return IvyEvent(title: "", startAt: start, endAt: start.addingTimeInterval(60 * 60))
    }
}
