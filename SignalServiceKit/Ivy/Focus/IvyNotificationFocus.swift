//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The days and hours a folder's chats may notify, for example weekdays
/// 9–18.
public struct IvyNotificationHours: Codable, Equatable, Sendable {

    /// Days the folder may notify, as `Calendar` numbers them: 1 is Sunday,
    /// 7 is Saturday.
    public var weekdays: Set<Int>
    /// Minutes after midnight. When `end` is before `start` the hours run
    /// past midnight; when they are equal, the whole day.
    public var start: Int
    public var end: Int

    public init(weekdays: Set<Int>, start: Int, end: Int) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
    }

    /// Monday to Friday, 9 to 18.
    public static let workdays = IvyNotificationHours(weekdays: [2, 3, 4, 5, 6], start: 9 * 60, end: 18 * 60)

    public func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday else {
            return true
        }
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end {
            return weekdays.contains(weekday)
        }
        if start < end {
            return weekdays.contains(weekday) && minutes >= start && minutes < end
        }
        // Past midnight: the early hours belong to the day before.
        if minutes >= start {
            return weekdays.contains(weekday)
        }
        if minutes < end {
            return weekdays.contains(weekday == 1 ? 7 : weekday - 1)
        }
        return false
    }
}

/// Whether a chat may notify now, by its folders' notification hours and
/// the Apple Focus that is on.
public enum IvyNotificationFocus {

    private static let focusFoldersKey = "IvyFocusFolderIds"

    /// Folders the current Apple Focus lets notify. Nil when no Focus with
    /// an Ivy filter is on. Kept on this device.
    public static var focusFolderIds: Set<Data>? {
        guard let hex = UserDefaults.standard.stringArray(forKey: focusFoldersKey) else {
            return nil
        }
        return Set(hex.compactMap { Data(hex: $0) })
    }

    public static func setFocusFolderIds(_ ids: Set<Data>?) {
        if let ids {
            UserDefaults.standard.set(ids.map(\.hexadecimalString).sorted(), forKey: focusFoldersKey)
        } else {
            UserDefaults.standard.removeObject(forKey: focusFoldersKey)
        }
    }

    public struct FolderRule: Equatable, Sendable {
        public let folderId: Data
        public let hours: IvyNotificationHours?

        public init(folderId: Data, hours: IvyNotificationHours?) {
            self.folderId = folderId
            self.hours = hours
        }
    }

    /// `folders` are the custom folders the chat is in. With a Focus on,
    /// only chats in its folders notify. Otherwise a chat notifies when one
    /// of its folders allows it now; folders without hours always do.
    static func allows(folders: [FolderRule], focusFolderIds: Set<Data>?, now: Date, calendar: Calendar) -> Bool {
        if let focusFolderIds, !folders.contains(where: { focusFolderIds.contains($0.folderId) }) {
            return false
        }
        guard !folders.isEmpty else {
            return true
        }
        return folders.contains { $0.hours?.allows(now, calendar: calendar) ?? true }
    }

    public static func allowsNotification(for thread: TSThread, now: Date = Date(), tx: DBReadTransaction) -> Bool {
        let focusFolderIds = focusFolderIds
        let folders = ChatFolderManager.shared.folders(tx: tx).filter { folder in
            folder.kind == .custom && folder.isMember(threadId: thread.uniqueId, isGroup: thread.isGroupThread)
        }
        guard focusFolderIds != nil || !folders.isEmpty else {
            return true
        }
        let store = IvyData.shared?.store
        let rules = folders.map { folder in
            FolderRule(folderId: folder.id, hours: ChatFolderExtras.fetch(folderId: folder.id, store: store).notificationHours)
        }
        return allows(folders: rules, focusFolderIds: focusFolderIds, now: now, calendar: .current)
    }
}
