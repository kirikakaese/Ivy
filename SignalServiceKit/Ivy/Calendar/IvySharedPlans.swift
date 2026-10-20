//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// An event proposed in a chat with a few times to choose from, or, once
/// agreed, the one time everyone takes. It travels as a normal message with
/// an `.ics` file, so other Signal apps show the text and the file; Ivy
/// recognizes the plan by the events' UIDs.
public struct IvyPlan: Equatable, Sendable {

    public struct Option: Equatable, Sendable {
        /// 1, 2, 3…, as the message lists them.
        public let number: Int
        public var start: Date
        public var end: Date
        public var isAllDay: Bool

        public init(number: Int, start: Date, end: Date, isAllDay: Bool = false) {
            self.number = number
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }
    }

    public let id: String
    public var title: String
    public var location: String
    public var options: [Option]
    /// The agreed time: one option.
    public var isConfirmed: Bool

    public init(id: String = UUID().uuidString, title: String, location: String = "", options: [Option], isConfirmed: Bool = false) {
        self.id = id
        self.title = title
        self.location = location
        self.options = options
        self.isConfirmed = isConfirmed
    }

    /// The agreed plan for one of the options.
    public func confirmed(option number: Int) -> IvyPlan? {
        guard let option = options.first(where: { $0.number == number }) else {
            return nil
        }
        return IvyPlan(id: id, title: title, location: location, options: [option], isConfirmed: true)
    }
}

public enum IvySharedPlans {

    static let uidSuffix = "@ivy-plan"
    static let optionSeparator = ".o"

    /// At most this many times to choose from.
    public static let maxOptions = 6

    // MARK: - Calendar files

    /// The events of a plan: proposed times are tentative.
    static func events(for plan: IvyPlan) -> [IvyEvent] {
        plan.options.map { option in
            IvyEvent(
                title: plan.title,
                location: plan.location,
                startAt: option.start,
                endAt: option.end,
                isAllDay: option.isAllDay,
                importedUID: plan.isConfirmed
                    ? plan.id + uidSuffix
                    : plan.id + optionSeparator + String(option.number) + uidSuffix,
            )
        }
    }

    public static func ics(for plan: IvyPlan) -> String {
        IvyICS.export(events(for: plan), status: plan.isConfirmed ? "CONFIRMED" : "TENTATIVE")
    }

    /// The plan in a calendar file, if it is one.
    public static func plan(fromICS text: String) -> IvyPlan? {
        guard let events = try? IvyICS.parse(text), let first = events.first else {
            return nil
        }
        var planId: String?
        var options = [IvyPlan.Option]()
        var isConfirmed = false
        for event in events {
            guard let uid = event.importedUID, uid.hasSuffix(uidSuffix) else {
                return nil
            }
            let base = String(uid.dropLast(uidSuffix.count))
            let id: String
            if let range = base.range(of: optionSeparator, options: .backwards), let number = Int(base[range.upperBound...]) {
                id = String(base[..<range.lowerBound])
                options.append(IvyPlan.Option(number: number, start: event.startAt, end: event.endAt, isAllDay: event.isAllDay))
            } else {
                id = base
                isConfirmed = true
                options.append(IvyPlan.Option(number: 1, start: event.startAt, end: event.endAt, isAllDay: event.isAllDay))
            }
            guard planId == nil || planId == id, !id.isEmpty else {
                return nil
            }
            planId = id
        }
        guard let planId, !(isConfirmed && options.count != 1) else {
            return nil
        }
        return IvyPlan(
            id: planId,
            title: first.title,
            location: first.location,
            options: options.sorted { $0.number < $1.number },
            isConfirmed: isConfirmed,
        )
    }

    /// The agreed time as a calendar event. Importing it again updates it.
    public static func event(forConfirmed plan: IvyPlan) -> IvyEvent? {
        guard plan.isConfirmed else {
            return nil
        }
        return events(for: plan).first
    }

    // MARK: - Answers

    /// Starts an answer, so Ivy can count it and people can read it.
    public static let answerMark = "✓"

    public static func answerText(number: Int, detail: String) -> String {
        "\(answerMark) \(number) · \(detail)"
    }

    /// The option an answer picks: "✓ 2 · …", "2", "2)" or "2." at the start.
    public static func answerNumber(in text: String) -> Int? {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for mark in [answerMark, "✔️", "✔"] where rest.hasPrefix(mark) {
            rest = rest.dropFirst(mark.count).drop(while: \.isWhitespace)
        }
        let digits = rest.prefix(while: \.isASCII).prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 2, let number = Int(digits) else {
            return nil
        }
        let after = rest.dropFirst(digits.count).first
        guard after == nil || after?.isWhitespace == true || ")..·:,!".contains(after!) else {
            return nil
        }
        return number
    }

    public struct Answer: Equatable, Sendable {
        public let voter: String
        public let number: Int
        public let timestamp: UInt64

        public init(voter: String, number: Int, timestamp: UInt64) {
            self.voter = voter
            self.number = number
            self.timestamp = timestamp
        }
    }

    /// Who picked which option. Each person's latest answer counts.
    public static func tally(_ answers: [Answer], plan: IvyPlan) -> [Int: [String]] {
        var latest = [String: Answer]()
        for answer in answers where plan.options.contains(where: { $0.number == answer.number }) {
            if let existing = latest[answer.voter], existing.timestamp > answer.timestamp {
                continue
            }
            latest[answer.voter] = answer
        }
        var result = [Int: [String]]()
        for answer in latest.values.sorted(by: { $0.voter < $1.voter }) {
            result[answer.number, default: []].append(answer.voter)
        }
        return result
    }

    // MARK: - Messages

    /// The plan in a message's calendar file, when it has one that is
    /// downloaded.
    public static func plan(in message: TSMessage, tx: DBReadTransaction) -> IvyPlan? {
        guard let rowId = message.sqliteRowId else {
            return nil
        }
        let attachments = DependenciesBridge.shared.attachmentStore.fetchReferencedAttachments(
            for: .messageBodyAttachment(messageRowId: rowId),
            tx: tx,
        )
        for referenced in attachments {
            let isCalendar = referenced.attachment.mimeType == IvyICS.mimeType
                || referenced.reference.sourceFilename?.lowercased().hasSuffix("." + IvyICS.fileExtension) == true
            guard
                isCalendar,
                let data = try? referenced.attachment.asStream()?.decryptedRawData(),
                let text = String(data: data, encoding: .utf8),
                let plan = plan(fromICS: text)
            else {
                continue
            }
            return plan
        }
        return nil
    }

    /// Replies to a plan message that pick an option.
    public static func answers(to planMessage: TSMessage, tx: DBReadTransaction, voterName: (TSMessage) -> String) -> [Answer] {
        guard let rowId = planMessage.sqliteRowId else {
            return []
        }
        let sql = """
        SELECT * FROM \(TSInteraction.databaseTableName)
        WHERE uniqueThreadId = ? AND id > ?
        ORDER BY id
        LIMIT 5000
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [planMessage.uniqueThreadId, rowId], transaction: tx)
        var answers = [Answer]()
        while let interaction = try? cursor.next() {
            guard
                let message = interaction as? TSMessage,
                message.quotedMessage?.timestampValue?.uint64Value == planMessage.timestamp,
                let number = answerNumber(in: message.body ?? "")
            else {
                continue
            }
            answers.append(Answer(voter: voterName(message), number: number, timestamp: message.timestamp))
        }
        return answers
    }
}
