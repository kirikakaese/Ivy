//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Names a chat in a way that is the same on all of the user's devices, as
/// opposed to a thread's unique id, which each device makes up itself.
public struct IvyChatReference: Hashable, Codable, Sendable, CustomStringConvertible {
    /// "a:" and an ACI, "e:" and a phone number, or "g:" and a base64 group
    /// id.
    public let rawValue: String

    public init?(rawValue: String) {
        guard ["a:", "e:", "g:"].contains(String(rawValue.prefix(2))), rawValue.count > 2 else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init?(thread: TSThread) {
        if let groupThread = thread as? TSGroupThread {
            self.rawValue = "g:" + groupThread.groupId.base64EncodedString()
        } else if let contactThread = thread as? TSContactThread {
            let address = contactThread.contactAddress
            if let aci = address.aci {
                self.rawValue = "a:" + aci.serviceIdString
            } else if let phoneNumber = address.phoneNumber {
                self.rawValue = "e:" + phoneNumber
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    public var description: String { rawValue }

    public func thread(tx: DBReadTransaction) -> TSThread? {
        let threadStore = DependenciesBridge.shared.threadStore
        let value = String(rawValue.dropFirst(2))
        switch rawValue.prefix(2) {
        case "a:":
            guard let aci = Aci.parseFrom(aciString: value) else { return nil }
            return threadStore.fetchContactThreads(serviceId: aci, tx: tx).first
        case "e:":
            return threadStore.fetchContactThreads(phoneNumber: value, tx: tx).first
        case "g:":
            guard let groupId = Data(base64Encoded: value) else { return nil }
            return threadStore.fetchThread(forGroupIdData: groupId, tx: tx)
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let reference = IvyChatReference(rawValue: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a chat reference"))
        }
        self = reference
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Names a message in the same way on all of the user's devices: its chat,
/// its timestamp and, for received messages, its author.
public struct IvyMessageReference: Hashable, Codable, Sendable {
    public let chat: IvyChatReference
    public let timestamp: UInt64
    /// The author's ACI, or nil for a message the user sent.
    public let authorAci: String?

    public init(chat: IvyChatReference, timestamp: UInt64, authorAci: String?) {
        self.chat = chat
        self.timestamp = timestamp
        self.authorAci = authorAci
    }

    public init?(message: TSMessage, thread: TSThread) {
        guard let chat = IvyChatReference(thread: thread) else {
            return nil
        }
        self.chat = chat
        self.timestamp = message.timestamp
        if let incoming = message as? TSIncomingMessage {
            guard let aci = incoming.authorAddress.aci else {
                return nil
            }
            self.authorAci = aci.serviceIdString
        } else {
            self.authorAci = nil
        }
    }

    public func message(tx: DBReadTransaction) -> TSMessage? {
        guard let thread = chat.thread(tx: tx) else {
            return nil
        }
        return try? DependenciesBridge.shared.interactionStore.fetchMessage(
            timestamp: timestamp,
            incomingMessageAuthor: authorAci.flatMap { Aci.parseFrom(aciString: $0) },
            threadUniqueId: thread.uniqueId,
            transaction: tx,
        )
    }
}
