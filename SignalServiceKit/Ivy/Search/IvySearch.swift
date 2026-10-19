//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

/// Filters shared by search and the library. Everything runs on the device.
public struct IvySearchFilter: Equatable, Sendable {

    public enum Content: String, CaseIterable, Sendable {
        case any
        case link
        case photo
        case file
    }

    /// Only messages in this chat.
    public var threadUniqueId: String?
    /// Only messages this person sent.
    public var author: Aci?
    public var since: Date?
    public var content: Content

    public init(threadUniqueId: String? = nil, author: Aci? = nil, since: Date? = nil, content: Content = .any) {
        self.threadUniqueId = threadUniqueId
        self.author = author
        self.since = since
        self.content = content
    }

    /// Whether only messages can match: tasks, events and notes have no
    /// sender or attachments.
    var limitsToMessages: Bool {
        author != nil || content != .any
    }
}

// MARK: - Search

/// One result of a search.
public enum IvySearchResult: Sendable {
    case message(threadUniqueId: String, messageUniqueId: String, snippet: String, timestamp: UInt64)
    case task(IvyTask)
    case event(IvyEvent)
    case chatNote(IvyChatReference, text: String)
}

public enum IvySearch {

    static let maxMessages = 200
    /// Messages read from the index before filters, so filtered searches
    /// still find enough.
    static let maxIndexedMatches = 2000

    /// Searches messages, then tasks, events and chat notes.
    public static func search(
        _ text: String,
        filter: IvySearchFilter,
        tasks: [IvyTask],
        events: [IvyEvent],
        chatNotes: [IvyChatReference: String],
        tx: DBReadTransaction,
    ) -> [IvySearchResult] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var results = [IvySearchResult]()
        if !query.isEmpty {
            FullTextSearchIndexer.search(for: query, maxResults: maxIndexedMatches, tx: tx) { message, snippet, stop in
                guard matches(message, filter: filter, tx: tx) else {
                    return
                }
                results.append(.message(
                    threadUniqueId: message.uniqueThreadId,
                    messageUniqueId: message.uniqueId,
                    snippet: snippet,
                    timestamp: message.timestamp,
                ))
                if results.count >= maxMessages {
                    stop = true
                }
            }
        } else if let kind = IvyLibrary.Kind(filter.content) {
            // A type filter alone: the newest links, photos or files.
            for item in IvyLibrary.items(kind: kind, filter: filter, limit: maxMessages, tx: tx) {
                results.append(.message(
                    threadUniqueId: item.threadUniqueId,
                    messageUniqueId: item.messageUniqueId,
                    snippet: item.title,
                    timestamp: item.timestamp,
                ))
            }
        }
        results.sort { lhs, rhs in
            if case .message(_, _, _, let left) = lhs, case .message(_, _, _, let right) = rhs {
                return left > right
            }
            return false
        }

        guard !query.isEmpty, !filter.limitsToMessages else {
            return results
        }
        let chatFilter = filter.threadUniqueId.flatMap { id in
            DependenciesBridge.shared.threadStore.fetchThread(uniqueId: id, tx: tx).flatMap(IvyChatReference.init(thread:))
        }
        if filter.threadUniqueId == nil {
            for task in tasks where contains(query, in: [task.title, task.notes] + task.subtasks.map(\.title)) {
                if let since = filter.since, let dueAt = task.dueAt, dueAt < since {
                    continue
                }
                results.append(.task(task))
            }
            for event in events where contains(query, in: [event.title, event.notes, event.location]) {
                if let since = filter.since, event.endAt < since {
                    continue
                }
                results.append(.event(event))
            }
        }
        for (chat, note) in chatNotes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where contains(query, in: [note]) {
            if filter.threadUniqueId != nil, chat != chatFilter {
                continue
            }
            results.append(.chatNote(chat, text: note))
        }
        return results
    }

    /// Whether every word of the query appears in one of the texts,
    /// ignoring case and accents.
    static func contains(_ query: String, in texts: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return false
        }
        let joined = texts.joined(separator: "\n")
        return words.allSatisfy { joined.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func matches(_ message: TSMessage, filter: IvySearchFilter, tx: DBReadTransaction) -> Bool {
        if message.editState == .pastRevision || message.wasRemotelyDeleted {
            return false
        }
        if let threadUniqueId = filter.threadUniqueId, message.uniqueThreadId != threadUniqueId {
            return false
        }
        if let author = filter.author {
            guard let incoming = message as? TSIncomingMessage, incoming.authorAddress.aci == author else {
                return false
            }
        }
        if let since = filter.since, Date(millisecondsSince1970: message.timestamp) < since {
            return false
        }
        switch filter.content {
        case .any:
            return true
        case .link:
            return message.linkPreview != nil || !IvyLibrary.links(in: message.body ?? "").isEmpty
        case .photo, .file:
            guard let rowId = message.sqliteRowId else {
                return false
            }
            return IvyLibrary.hasAttachment(messageRowId: rowId, kind: filter.content == .photo ? .photos : .files, tx: tx)
        }
    }
}

// MARK: - Library

/// Every link, photo and file from all chats, newest first.
public enum IvyLibrary {

    public enum Kind: String, CaseIterable, Sendable {
        case links
        case photos
        case files

        init?(_ content: IvySearchFilter.Content) {
            switch content {
            case .any: return nil
            case .link: self = .links
            case .photo: self = .photos
            case .file: self = .files
            }
        }
    }

    public struct Item: Equatable, Sendable {
        public let kind: Kind
        public let threadUniqueId: String
        public let messageUniqueId: String
        public let timestamp: UInt64
        /// The link, or the file's name.
        public let title: String
        public let url: URL?
    }

    /// Attachment content types, as `Attachment.ContentType` stores them.
    private static let visualContentTypes = "\(Attachment.ContentType.image.rawValue), \(Attachment.ContentType.video.rawValue)"
    private static let fileContentType = Attachment.ContentType.file.rawValue
    /// Attachments on the message itself, not quotes or previews.
    private static let bodyAttachmentOwnerType = 0
    private static let pastRevisionEditState = 2

    /// Messages read before filters, so filtered lists still fill up.
    static let scanFactor = 4

    public static func links(in text: String) -> [URL] {
        guard text.contains("."), let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).filter { url in
            url.scheme == "http" || url.scheme == "https"
        }
    }

    static func hasAttachment(messageRowId: Int64, kind: Kind, tx: DBReadTransaction) -> Bool {
        let condition = kind == .photos ? "contentType IN (\(visualContentTypes))" : "contentType = \(fileContentType)"
        let sql = """
        SELECT 1 FROM MessageAttachmentReference
        WHERE ownerRowId = ? AND ownerType = \(bodyAttachmentOwnerType) AND \(condition)
        LIMIT 1
        """
        return ((try? Int.fetchOne(tx.database, sql: sql, arguments: [messageRowId])) ?? nil) != nil
    }

    /// The newest items of a kind, or of every kind when `kind` is nil.
    public static func items(kind: Kind?, filter: IvySearchFilter, limit: Int, tx: DBReadTransaction) -> [Item] {
        var items = [Item]()
        for kind in kind.map({ [$0] }) ?? Kind.allCases {
            items += fetch(kind: kind, filter: filter, limit: limit, tx: tx)
        }
        return Array(items.sorted { ($0.timestamp, $0.messageUniqueId) > ($1.timestamp, $1.messageUniqueId) }.prefix(limit))
    }

    private static func fetch(kind: Kind, filter: IvySearchFilter, limit: Int, tx: DBReadTransaction) -> [Item] {
        var conditions = ["i.editState IS NOT \(pastRevisionEditState)", "IFNULL(i.wasRemotelyDeleted, 0) = 0"]
        var arguments = [DatabaseValueConvertible?]()
        if let threadUniqueId = filter.threadUniqueId {
            conditions.append("i.uniqueThreadId = ?")
            arguments.append(threadUniqueId)
        }
        if let since = filter.since {
            conditions.append("i.timestamp >= ?")
            arguments.append(Int64(since.timeIntervalSince1970 * 1000))
        }

        let sql: String
        switch kind {
        case .links:
            conditions.append("(i.body LIKE '%http%' OR i.linkPreview IS NOT NULL)")
            sql = """
            SELECT i.uniqueId AS messageId, NULL AS fileName FROM model_TSInteraction AS i
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY i.id DESC
            LIMIT \(limit * scanFactor)
            """
        case .photos, .files:
            let typeCondition = kind == .photos ? "r.contentType IN (\(visualContentTypes))" : "r.contentType = \(fileContentType)"
            sql = """
            SELECT i.uniqueId AS messageId, r.sourceFilename AS fileName FROM MessageAttachmentReference AS r
            JOIN model_TSInteraction AS i ON i.id = r.ownerRowId
            WHERE r.ownerType = \(bodyAttachmentOwnerType) AND \(typeCondition)
            AND IFNULL(r.isViewOnce, 0) = 0
            AND \(conditions.joined(separator: " AND "))
            ORDER BY r.receivedAtTimestamp DESC, r.ownerRowId DESC
            LIMIT \(limit * scanFactor)
            """
        }

        var items = [Item]()
        do {
            let rows = try Row.fetchAll(tx.database, sql: sql, arguments: StatementArguments(arguments))
            for row in rows {
                guard items.count < limit else {
                    break
                }
                let messageId: String = row["messageId"]
                guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageId, transaction: tx) else {
                    continue
                }
                if let author = filter.author {
                    guard let incoming = message as? TSIncomingMessage, incoming.authorAddress.aci == author else {
                        continue
                    }
                }
                switch kind {
                case .links:
                    var urls = links(in: message.body ?? "")
                    if urls.isEmpty, let previewUrl = message.linkPreview?.urlString.flatMap({ URL(string: $0) }) {
                        urls = [previewUrl]
                    }
                    for url in urls where items.count < limit {
                        items.append(Item(
                            kind: .links,
                            threadUniqueId: message.uniqueThreadId,
                            messageUniqueId: message.uniqueId,
                            timestamp: message.timestamp,
                            title: url.absoluteString,
                            url: url,
                        ))
                    }
                case .photos, .files:
                    let fileName: String? = row["fileName"]
                    items.append(Item(
                        kind: kind,
                        threadUniqueId: message.uniqueThreadId,
                        messageUniqueId: message.uniqueId,
                        timestamp: message.timestamp,
                        title: fileName?.nilIfEmpty ?? "",
                        url: nil,
                    ))
                }
            }
        } catch {
            owsFailDebug("Couldn't read the library: \(error.grdbErrorForLogging)")
        }
        return items
    }
}
