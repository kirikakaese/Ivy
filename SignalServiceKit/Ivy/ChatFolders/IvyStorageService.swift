//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SwiftProtobuf

// SwiftProtobuf messages for IvyStorageService.proto, written in the same
// shape as the code that protoc-gen-swift produces for upstream protos.

public struct IvyStorageProtos_StorageRecord: Sendable {
    public var chatFolder: IvyStorageProtos_ChatFolderRecord?

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}
}

public enum IvyStorageProtos_KeyType {
    /// `ManifestRecord.Key.Type.CHAT_FOLDER`
    public static let chatFolder = 8
}

public struct IvyStorageProtos_Recipient: Sendable {
    public enum Identifier: Equatable, Sendable {
        case contact(IvyStorageProtos_Recipient.Contact)
        case legacyGroupID(Data)
        case groupMasterKey(Data)
    }

    public struct Contact: Sendable {
        public var serviceID: String = String()
        public var e164: String = String()
        public var serviceIDBinary: Data = Data()

        public var unknownFields = SwiftProtobuf.UnknownStorage()

        public init() {}
    }

    public var identifier: Identifier?

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}
}

public struct IvyStorageProtos_ChatFolderRecord: Sendable {
    public enum FolderType: SwiftProtobuf.Enum, Swift.CaseIterable {
        public typealias RawValue = Int

        case unknown // = 0
        case all // = 1
        case custom // = 2
        case UNRECOGNIZED(Int)

        public init() {
            self = .unknown
        }

        public init?(rawValue: Int) {
            switch rawValue {
            case 0: self = .unknown
            case 1: self = .all
            case 2: self = .custom
            default: self = .UNRECOGNIZED(rawValue)
            }
        }

        public var rawValue: Int {
            switch self {
            case .unknown: return 0
            case .all: return 1
            case .custom: return 2
            case .UNRECOGNIZED(let i): return i
            }
        }

        public static let allCases: [IvyStorageProtos_ChatFolderRecord.FolderType] = [.unknown, .all, .custom]
    }

    public var identifier: Data = Data()
    public var name: String = String()
    public var position: UInt32 = 0
    public var showOnlyUnread: Bool = false
    public var showMutedChats: Bool = false
    public var includeAllIndividualChats: Bool = false
    public var includeAllGroupChats: Bool = false
    public var folderType: FolderType = .unknown
    public var includedRecipients: [IvyStorageProtos_Recipient] = []
    public var excludedRecipients: [IvyStorageProtos_Recipient] = []
    public var deletedAtTimestampMs: UInt64 = 0

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}
}

// MARK: - SwiftProtobuf runtime support

private let _protobuf_package = "IvyStorageProtos"

extension IvyStorageProtos_StorageRecord: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
    public static let protoMessageName: String = _protobuf_package + ".StorageRecord"

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 8: try decoder.decodeSingularMessageField(value: &self.chatFolder)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if let chatFolder {
            try visitor.visitSingularMessageField(value: chatFolder, fieldNumber: 8)
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.chatFolder == rhs.chatFolder && lhs.unknownFields == rhs.unknownFields
    }
}

extension IvyStorageProtos_Recipient: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
    public static let protoMessageName: String = _protobuf_package + ".Recipient"

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1:
                var value: IvyStorageProtos_Recipient.Contact?
                var hadOneofValue = false
                if let current = self.identifier {
                    hadOneofValue = true
                    if case .contact(let m) = current { value = m }
                }
                try decoder.decodeSingularMessageField(value: &value)
                if let value {
                    if hadOneofValue { try decoder.handleConflictingOneOf() }
                    self.identifier = .contact(value)
                }
            case 2:
                var value: Data?
                try decoder.decodeSingularBytesField(value: &value)
                if let value {
                    if self.identifier != nil { try decoder.handleConflictingOneOf() }
                    self.identifier = .legacyGroupID(value)
                }
            case 3:
                var value: Data?
                try decoder.decodeSingularBytesField(value: &value)
                if let value {
                    if self.identifier != nil { try decoder.handleConflictingOneOf() }
                    self.identifier = .groupMasterKey(value)
                }
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        switch self.identifier {
        case .contact(let value)?:
            try visitor.visitSingularMessageField(value: value, fieldNumber: 1)
        case .legacyGroupID(let value)?:
            try visitor.visitSingularBytesField(value: value, fieldNumber: 2)
        case .groupMasterKey(let value)?:
            try visitor.visitSingularBytesField(value: value, fieldNumber: 3)
        case nil:
            break
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.identifier == rhs.identifier && lhs.unknownFields == rhs.unknownFields
    }
}

extension IvyStorageProtos_Recipient.Contact: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
    public static let protoMessageName: String = IvyStorageProtos_Recipient.protoMessageName + ".Contact"

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &self.serviceID)
            case 2: try decoder.decodeSingularStringField(value: &self.e164)
            case 3: try decoder.decodeSingularBytesField(value: &self.serviceIDBinary)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !self.serviceID.isEmpty {
            try visitor.visitSingularStringField(value: self.serviceID, fieldNumber: 1)
        }
        if !self.e164.isEmpty {
            try visitor.visitSingularStringField(value: self.e164, fieldNumber: 2)
        }
        if !self.serviceIDBinary.isEmpty {
            try visitor.visitSingularBytesField(value: self.serviceIDBinary, fieldNumber: 3)
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.serviceID == rhs.serviceID
            && lhs.e164 == rhs.e164
            && lhs.serviceIDBinary == rhs.serviceIDBinary
            && lhs.unknownFields == rhs.unknownFields
    }
}

extension IvyStorageProtos_ChatFolderRecord: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
    public static let protoMessageName: String = _protobuf_package + ".ChatFolderRecord"

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularBytesField(value: &self.identifier)
            case 2: try decoder.decodeSingularStringField(value: &self.name)
            case 3: try decoder.decodeSingularUInt32Field(value: &self.position)
            case 4: try decoder.decodeSingularBoolField(value: &self.showOnlyUnread)
            case 5: try decoder.decodeSingularBoolField(value: &self.showMutedChats)
            case 6: try decoder.decodeSingularBoolField(value: &self.includeAllIndividualChats)
            case 7: try decoder.decodeSingularBoolField(value: &self.includeAllGroupChats)
            case 8: try decoder.decodeSingularEnumField(value: &self.folderType)
            case 9: try decoder.decodeRepeatedMessageField(value: &self.includedRecipients)
            case 10: try decoder.decodeRepeatedMessageField(value: &self.excludedRecipients)
            case 11: try decoder.decodeSingularUInt64Field(value: &self.deletedAtTimestampMs)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !self.identifier.isEmpty {
            try visitor.visitSingularBytesField(value: self.identifier, fieldNumber: 1)
        }
        if !self.name.isEmpty {
            try visitor.visitSingularStringField(value: self.name, fieldNumber: 2)
        }
        if self.position != 0 {
            try visitor.visitSingularUInt32Field(value: self.position, fieldNumber: 3)
        }
        if self.showOnlyUnread {
            try visitor.visitSingularBoolField(value: self.showOnlyUnread, fieldNumber: 4)
        }
        if self.showMutedChats {
            try visitor.visitSingularBoolField(value: self.showMutedChats, fieldNumber: 5)
        }
        if self.includeAllIndividualChats {
            try visitor.visitSingularBoolField(value: self.includeAllIndividualChats, fieldNumber: 6)
        }
        if self.includeAllGroupChats {
            try visitor.visitSingularBoolField(value: self.includeAllGroupChats, fieldNumber: 7)
        }
        if self.folderType != .unknown {
            try visitor.visitSingularEnumField(value: self.folderType, fieldNumber: 8)
        }
        if !self.includedRecipients.isEmpty {
            try visitor.visitRepeatedMessageField(value: self.includedRecipients, fieldNumber: 9)
        }
        if !self.excludedRecipients.isEmpty {
            try visitor.visitRepeatedMessageField(value: self.excludedRecipients, fieldNumber: 10)
        }
        if self.deletedAtTimestampMs != 0 {
            try visitor.visitSingularUInt64Field(value: self.deletedAtTimestampMs, fieldNumber: 11)
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.identifier == rhs.identifier
            && lhs.name == rhs.name
            && lhs.position == rhs.position
            && lhs.showOnlyUnread == rhs.showOnlyUnread
            && lhs.showMutedChats == rhs.showMutedChats
            && lhs.includeAllIndividualChats == rhs.includeAllIndividualChats
            && lhs.includeAllGroupChats == rhs.includeAllGroupChats
            && lhs.folderType == rhs.folderType
            && lhs.includedRecipients == rhs.includedRecipients
            && lhs.excludedRecipients == rhs.excludedRecipients
            && lhs.deletedAtTimestampMs == rhs.deletedAtTimestampMs
            && lhs.unknownFields == rhs.unknownFields
    }
}
