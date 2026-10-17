//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What one Ivy device tells the user's other Ivy devices. It travels inside
/// a Signal sync message, end-to-end encrypted to the user's own devices, in
/// a field that official clients do not know and ignore.
public struct IvySyncPayload: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, Sendable {
        /// Edits made on the sending device.
        case changes
        /// A device without Ivy data asks the others for everything.
        case requestSnapshot
        /// All Ivy data, sent in answer to `requestSnapshot`.
        case snapshot
    }

    /// The protocol version. Devices ignore payloads with a newer major
    /// version than they understand.
    public var version: Int
    public var kind: Kind
    public var changes: [IvyDataChange]

    public static let currentVersion = 1

    /// The field number in `SyncMessage` that carries the payload. Official
    /// clients skip unknown fields.
    public static let syncMessageFieldNumber = 7_301

    /// Payloads larger than this are split, to stay well below Signal's
    /// message size limit.
    static let maxEncodedSize = 64 * 1024

    public init(kind: Kind, changes: [IvyDataChange] = []) {
        self.version = Self.currentVersion
        self.kind = kind
        self.changes = changes
    }

    public func encoded() throws -> Data {
        return try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) -> IvySyncPayload? {
        guard let payload = try? JSONDecoder().decode(IvySyncPayload.self, from: data) else {
            return nil
        }
        guard payload.version <= currentVersion else {
            return nil
        }
        return payload
    }

    /// Splits changes into payloads that each stay below the size limit.
    public static func payloads(kind: Kind, changes: [IvyDataChange]) -> [IvySyncPayload] {
        guard !changes.isEmpty else {
            return [IvySyncPayload(kind: kind)]
        }
        var result = [IvySyncPayload]()
        var current = [IvyDataChange]()
        var currentSize = 0
        for change in changes {
            let size = (try? JSONEncoder().encode(change).count) ?? 0
            if !current.isEmpty, currentSize + size > maxEncodedSize {
                result.append(IvySyncPayload(kind: kind, changes: current))
                current = []
                currentSize = 0
            }
            current.append(change)
            currentSize += size + 1
        }
        result.append(IvySyncPayload(kind: kind, changes: current))
        return result
    }

    // MARK: - Protobuf field

    /// Wraps the payload as protobuf field `syncMessageFieldNumber` with wire
    /// type 2 (length-delimited), ready to append to a serialized
    /// `SyncMessage`.
    public func protobufField() throws -> Data {
        let body = try encoded()
        return Self.varint(UInt64(Self.syncMessageFieldNumber) << 3 | 2) + Self.varint(UInt64(body.count)) + body
    }

    /// Finds the payload field in serialized protobuf fields, such as the
    /// unknown fields of a received `SyncMessage`.
    public static func fromProtobufFields(_ data: Data) -> IvySyncPayload? {
        var index = data.startIndex
        while index < data.endIndex {
            guard let tag = readVarint(data, &index) else {
                return nil
            }
            let fieldNumber = tag >> 3
            switch tag & 7 {
            case 0:
                guard readVarint(data, &index) != nil else { return nil }
            case 1:
                index = data.index(index, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
            case 2:
                guard let length = readVarint(data, &index), length <= UInt64(data.endIndex - index) else {
                    return nil
                }
                let end = index + Int(length)
                if fieldNumber == UInt64(syncMessageFieldNumber) {
                    return decode(data.subdata(in: index..<end))
                }
                index = end
            case 5:
                index = data.index(index, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
            default:
                return nil
            }
        }
        return nil
    }

    private static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes = [UInt8]()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }

    private static func readVarint(_ data: Data, _ index: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex, shift < 64 {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        return nil
    }
}
