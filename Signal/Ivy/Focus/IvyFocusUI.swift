//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UserNotifications

/// Folder notification hours and the quiet summary of muted chats.
enum IvyFocusUI {

    private static var isStarted = false

    /// Called when the app is ready: keeps the quiet summary's counts fresh.
    static func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                IvyQuietSummary.reschedule()
            }
        }
        IvyQuietSummary.reschedule()
    }

    /// Tapping the quiet summary opens Ivy at the chat list.
    static func handle(_ response: UNNotificationResponse) -> Bool {
        IvyQuietSummary.isSummary(response.notification.request)
    }

    // MARK: - Text

    static func timeText(minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    /// The weekdays in the order the user's calendar shows them.
    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func hoursText(_ hours: IvyNotificationHours?) -> String {
        guard let hours else {
            return IvyLocalizedString("FOCUS_HOURS_ANY_TIME", comment: "A chat folder's chats may notify at any time.")
        }
        let symbols = Calendar.current.shortWeekdaySymbols
        let days: String
        if hours.weekdays == IvyNotificationHours.workdays.weekdays {
            days = IvyLocalizedString("FOCUS_HOURS_WEEKDAYS", comment: "Monday to Friday, in a chat folder's notification hours.")
        } else if hours.weekdays.count == 7 {
            days = IvyLocalizedString("FOCUS_HOURS_EVERY_DAY", comment: "Every day, in a chat folder's notification hours.")
        } else {
            days = orderedWeekdays.filter { hours.weekdays.contains($0) }.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        if hours.start == hours.end {
            return days
        }
        return "\(days), \(timeText(minutes: hours.start))–\(timeText(minutes: hours.end))"
    }

    static func timePickerItem(title: String, minutes: Int, onChange: @escaping (Int) -> Void) -> OWSTableItem {
        OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            let label = UILabel()
            label.text = title
            label.font = .dynamicTypeBody
            label.textColor = .Signal.label
            let picker = UIDatePicker()
            picker.datePickerMode = .time
            picker.preferredDatePickerStyle = .compact
            picker.date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            picker.addAction(UIAction { [weak picker] _ in
                guard let picker else { return }
                let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
                onChange((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }, for: .valueChanged)
            let stack = UIStackView(arrangedSubviews: [label, UIView(), picker])
            stack.axis = .horizontal
            stack.alignment = .center
            cell.contentView.addSubview(stack)
            stack.autoPinEdgesToSuperviewMargins()
            return cell
        })
    }
}

// MARK: - Folder notification hours

/// Chooses when a folder's chats may notify: any time, or on chosen days
/// between two times.
final class IvyNotificationHoursViewController: OWSTableViewController2 {

    private var hours: IvyNotificationHours?
    private let onChange: (IvyNotificationHours?) -> Void

    init(hours: IvyNotificationHours?, onChange: @escaping (IvyNotificationHours?) -> Void) {
        self.hours = hours
        self.onChange = onChange
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("CHAT_FOLDER_NOTIFY", comment: "Item that sets when a chat folder's chats may notify.")
        updateTableContents()
    }

    private func change(_ update: (inout IvyNotificationHours) -> Void) {
        var value = hours ?? .workdays
        update(&value)
        hours = value
        onChange(hours)
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: title)

        let mainSection = OWSTableSection()
        mainSection.footerTitle = IvyLocalizedString("FOCUS_HOURS_FOOTER", comment: "Explains a chat folder's notification hours.")
        mainSection.add(.switch(
            withText: IvyLocalizedString("FOCUS_HOURS_LIMIT", comment: "Switch that lets a chat folder's chats notify only on chosen days and hours."),
            isOn: { [weak self] in self?.hours != nil },
            actionBlock: { [weak self] uiSwitch in
                guard let self else { return }
                hours = uiSwitch.isOn ? .workdays : nil
                onChange(hours)
                updateTableContents()
            },
        ))
        contents.add(mainSection)

        if let hours {
            let timeSection = OWSTableSection()
            timeSection.add(IvyFocusUI.timePickerItem(
                title: IvyLocalizedString("FOCUS_HOURS_FROM", comment: "When a chat folder's notification hours start."),
                minutes: hours.start,
            ) { [weak self] minutes in
                self?.change { $0.start = minutes }
            })
            timeSection.add(IvyFocusUI.timePickerItem(
                title: IvyLocalizedString("FOCUS_HOURS_UNTIL", comment: "When a chat folder's notification hours end."),
                minutes: hours.end,
            ) { [weak self] minutes in
                self?.change { $0.end = minutes }
            })
            contents.add(timeSection)

            let daysSection = OWSTableSection()
            daysSection.headerTitle = IvyLocalizedString("FOCUS_HOURS_DAYS", comment: "Header of the days a chat folder may notify.")
            let symbols = Calendar.current.weekdaySymbols
            for weekday in IvyFocusUI.orderedWeekdays {
                daysSection.add(.switch(
                    withText: symbols[weekday - 1],
                    isOn: { [weak self] in self?.hours?.weekdays.contains(weekday) ?? false },
                    actionBlock: { [weak self] uiSwitch in
                        self?.change { hours in
                            if uiSwitch.isOn {
                                hours.weekdays.insert(weekday)
                            } else {
                                hours.weekdays.remove(weekday)
                            }
                        }
                    },
                ))
            }
            contents.add(daysSection)
        }
        self.contents = contents
    }
}

// MARK: - Quiet summary

extension NotificationSettingsViewController {

    /// "Muted Chats Summary", in the notification settings.
    func ivyAddQuietSummaryItem(to contents: OWSTableContents) {
        let minutes = SSKEnvironment.shared.databaseStorageRef.read { tx in IvyQuietSummary.time(tx: tx) }
        let section = OWSTableSection()
        section.add(.disclosureItem(
            withText: IvyQuietSummarySettingsViewController.title,
            accessoryText: minutes.map { IvyFocusUI.timeText(minutes: $0) }
                ?? IvyLocalizedString("QUIET_SUMMARY_OFF", comment: "Shown next to the muted chats summary setting when it is off."),
        ) { [weak self] in
            self?.navigationController?.pushViewController(IvyQuietSummarySettingsViewController(), animated: true)
        })
        contents.add(section)
    }
}

/// Turns the daily summary of muted chats on or off, and sets its time.
final class IvyQuietSummarySettingsViewController: OWSTableViewController2 {

    static var title: String {
        IvyLocalizedString("QUIET_SUMMARY_SETTING", comment: "Setting for the daily summary of muted chats.")
    }

    /// 18:00 unless the user chose another time.
    private static let defaultMinutes = 18 * 60

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        updateTableContents()
    }

    private func setMinutes(_ minutes: Int?) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in IvyQuietSummary.setTime(minutes, tx: tx) }
        IvyQuietSummary.reschedule()
    }

    private func updateTableContents() {
        let minutes = SSKEnvironment.shared.databaseStorageRef.read { tx in IvyQuietSummary.time(tx: tx) }
        let contents = OWSTableContents(title: title)
        let section = OWSTableSection()
        section.footerTitle = IvyLocalizedString("QUIET_SUMMARY_FOOTER", comment: "Explains the daily summary of muted chats.")
        section.add(.switch(
            withText: Self.title,
            isOn: { minutes != nil },
            actionBlock: { [weak self] uiSwitch in
                self?.setMinutes(uiSwitch.isOn ? Self.defaultMinutes : nil)
                self?.updateTableContents()
            },
        ))
        if let minutes {
            section.add(IvyFocusUI.timePickerItem(
                title: IvyLocalizedString("QUIET_SUMMARY_TIME", comment: "When the daily summary of muted chats arrives."),
                minutes: minutes,
            ) { [weak self] minutes in
                self?.setMinutes(minutes)
            })
        }
        contents.add(section)
        self.contents = contents
    }
}
