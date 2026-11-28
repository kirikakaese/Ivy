//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Puts agreed shared plans into the calendar: whenever a message with a
/// confirmed plan arrives (or is sent from another device), its event is
/// added, or updated if it was added before. Only plans confirmed by this
/// account, or by whoever first proposed them in the same chat, are added;
/// anyone else's file needs "Add to Calendar". Files not downloaded yet are
/// looked at again later.
public final class IvyPlanWatcher {

    public static let shared = IvyPlanWatcher()

    private let store = KeyValueStore(collection: "IvyPlanWatcher")
    private static let lastRowIdKey = "lastRowId"
    private static let pendingKey = "pending"
    /// "proposer." + plan id → "<thread>|<author ACI>", empty author for this account.
    private static let proposerKeyPrefix = "proposer."

    /// Messages looked at per scan.
    static let batchSize = 200
    /// Files still downloading, looked at again later.
    static let maxPending = 50

    private let isScanning = AtomicBool(false, lock: .sharedGlobal)

    /// Looks at messages with calendar files that arrived since the last
    /// scan. The first scan only remembers where to start. Main thread
    /// only, as it updates the calendar.
    public func scan() {
        AssertIsOnMainThread()
        guard isScanning.tryToSetFlag() else {
            return
        }
        defer { isScanning.set(false) }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let (lastRowId, pending) = databaseStorage.read { tx in
            (
                store.getInt64(Self.lastRowIdKey, transaction: tx),
                (store.getString(Self.pendingKey, transaction: tx) ?? "").split(separator: ",").compactMap { Int64($0) },
            )
        }
        guard let lastRowId else {
            databaseStorage.write { tx in
                store.setInt64(Int64(InteractionFinder.maxInteractionRowId(transaction: tx)), key: Self.lastRowIdKey, transaction: tx)
            }
            return
        }

        var confirmed = [IvyPlan]()
        var stillPending = [Int64]()
        var newProposers = [String: String]()
        var newLastRowId = lastRowId
        databaseStorage.read { tx in
            let candidates = pending + Self.calendarMessageRowIds(after: lastRowId, tx: tx)
            for rowId in candidates {
                newLastRowId = max(newLastRowId, rowId)
                switch Self.planState(messageRowId: rowId, tx: tx) {
                case .plan(let plan):
                    guard let origin = Self.origin(messageRowId: rowId, tx: tx) else {
                        break
                    }
                    let proposer = newProposers[plan.id] ?? store.getString(Self.proposerKeyPrefix + plan.id, transaction: tx)
                    if !plan.isConfirmed {
                        // The first proposal decides who may confirm; a later one with the same id cannot take over.
                        if proposer == nil {
                            newProposers[plan.id] = origin
                        }
                    } else if origin.hasSuffix("|") || origin == proposer {
                        confirmed.append(plan)
                    }
                case .notDownloaded:
                    stillPending.append(rowId)
                case .none:
                    break
                }
            }
        }

        for plan in confirmed {
            _ = try? IvyEventManager.shared.importCalendar(IvySharedPlans.ics(for: plan))
        }
        databaseStorage.write { tx in
            store.setInt64(newLastRowId, key: Self.lastRowIdKey, transaction: tx)
            for (planId, origin) in newProposers {
                store.setString(origin, key: Self.proposerKeyPrefix + planId, transaction: tx)
            }
            let pendingText = Set(stillPending).sorted().suffix(Self.maxPending).map(String.init).joined(separator: ",")
            store.setString(pendingText, key: Self.pendingKey, transaction: tx)
        }
    }

    private enum PlanState {
        case none
        case notDownloaded
        case plan(IvyPlan)
    }

    /// "<thread>|<author ACI>" of a message; the author is empty for messages this account sent.
    private static func origin(messageRowId: Int64, tx: DBReadTransaction) -> String? {
        // Incoming messages always have an author (old ones only a phone number); outgoing ones have none.
        let sql = "SELECT uniqueThreadId, authorUUID, authorPhoneNumber FROM model_TSInteraction WHERE id = ?"
        guard let row = try? Row.fetchOne(tx.database, sql: sql, arguments: [messageRowId]) else {
            return nil
        }
        let thread: String = row["uniqueThreadId"]
        let author: String? = row["authorUUID"] ?? row["authorPhoneNumber"]
        return thread + "|" + (author ?? "")
    }

    private static func calendarMessageRowIds(after rowId: Int64, tx: DBReadTransaction) -> [Int64] {
        let sql = """
        SELECT DISTINCT ownerRowId FROM MessageAttachmentReference
        WHERE ownerType = 0 AND ownerRowId > ?
        AND LOWER(IFNULL(sourceFilename, '')) LIKE '%.ics'
        ORDER BY ownerRowId
        LIMIT \(batchSize)
        """
        return (try? Int64.fetchAll(tx.database, sql: sql, arguments: [rowId])) ?? []
    }

    private static func planState(messageRowId: Int64, tx: DBReadTransaction) -> PlanState {
        let attachments = DependenciesBridge.shared.attachmentStore.fetchReferencedAttachments(
            for: .messageBodyAttachment(messageRowId: messageRowId),
            tx: tx,
        )
        for referenced in attachments where referenced.reference.sourceFilename?.lowercased().hasSuffix("." + IvyICS.fileExtension) == true {
            guard let stream = referenced.attachment.asStream() else {
                return .notDownloaded
            }
            // A plan is a few kilobytes; anything far larger is not one and is not worth reading into memory.
            guard stream.unencryptedByteCount <= 1_000_000 else {
                continue
            }
            guard
                let data = try? stream.decryptedRawData(),
                let text = String(data: data, encoding: .utf8),
                let plan = IvySharedPlans.plan(fromICS: text)
            else {
                continue
            }
            return .plan(plan)
        }
        return .none
    }
}
