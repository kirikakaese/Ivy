//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class ChatFolderManagerTest: XCTestCase {

    private var db: InMemoryDB!
    private var manager: ChatFolderManager!
    private var syncedIds: [Data] = []

    override func setUp() {
        super.setUp()
        db = InMemoryDB()
        syncedIds = []
        manager = ChatFolderManager(
            store: KeyValueStore(collection: "ChatFolderManagerTest"),
            recordPendingStorageUpdates: { [unowned self] ids in self.syncedIds += ids },
        )
    }

    func testFirstFolderAddsAllChats() {
        let work = ChatFolder(name: "Work")
        db.write { tx in manager.save(work, tx: tx) }

        let folders = db.read { tx in manager.folders(tx: tx) }
        XCTAssertEqual(folders.map(\.kind), [.allChats, .custom])
        XCTAssertEqual(folders.last?.name, "Work")
        XCTAssertEqual(Set(syncedIds), Set(folders.map(\.id)))
        XCTAssertTrue(db.read { tx in manager.hasCustomFolders(tx: tx) })
    }

    func testNewFoldersGoLast() {
        db.write { tx in
            manager.save(ChatFolder(name: "A"), tx: tx)
            manager.save(ChatFolder(name: "B"), tx: tx)
        }
        let names = db.read { tx in manager.folders(tx: tx) }.map(\.name)
        XCTAssertEqual(names, ["", "A", "B"])
    }

    func testReorder() {
        let a = ChatFolder(name: "A")
        let b = ChatFolder(name: "B")
        db.write { tx in
            manager.save(a, tx: tx)
            manager.save(b, tx: tx)
            manager.reorder([b.id, a.id], tx: tx)
        }
        let folders = db.read { tx in manager.folders(tx: tx) }
        XCTAssertEqual(folders.map(\.name), ["B", "A", ""])
        XCTAssertEqual(folders.map(\.position), [0, 1, 2])
    }

    func testDeleteKeepsATombstone() {
        let a = ChatFolder(name: "A", includedThreadIds: ["x"])
        db.write { tx in manager.save(a, tx: tx) }
        syncedIds = []
        db.write { tx in manager.delete(id: a.id, tx: tx) }

        XCTAssertEqual(syncedIds, [a.id])
        let stored = db.read { tx in manager.folder(id: a.id, tx: tx) }
        XCTAssertNotNil(stored?.deletedAtTimestampMs)
        XCTAssertEqual(stored?.includedThreadIds, [])
        XCTAssertFalse(db.read { tx in manager.folders(tx: tx) }.contains { $0.id == a.id })
        XCTAssertFalse(db.read { tx in manager.hasCustomFolders(tx: tx) })
    }

    func testAllChatsCannotBeDeleted() {
        db.write { tx in manager.save(ChatFolder(name: "A"), tx: tx) }
        let allChats = db.read { tx in manager.folders(tx: tx) }.first!
        db.write { tx in manager.delete(id: allChats.id, tx: tx) }
        XCTAssertEqual(db.read { tx in manager.folders(tx: tx) }.first?.id, allChats.id)
    }

    func testAddAndRemoveChats() {
        let folder = ChatFolder(name: "People", includeAllIndividualChats: true)
        db.write { tx in
            manager.save(folder, tx: tx)
            manager.remove(threadId: "contact", isGroup: false, fromFolder: folder.id, tx: tx)
            manager.add(threadId: "group", toFolder: folder.id, tx: tx)
        }
        var stored = db.read { tx in manager.folder(id: folder.id, tx: tx) }!
        XCTAssertEqual(stored.excludedThreadIds, ["contact"])
        XCTAssertEqual(stored.includedThreadIds, ["group"])

        db.write { tx in
            manager.add(threadId: "contact", toFolder: folder.id, tx: tx)
            manager.remove(threadId: "group", isGroup: true, fromFolder: folder.id, tx: tx)
        }
        stored = db.read { tx in manager.folder(id: folder.id, tx: tx) }!
        XCTAssertEqual(stored.excludedThreadIds, [])
        XCTAssertEqual(stored.includedThreadIds, ["contact"])
    }

    func testRemoteAllChatsReplacesLocalOne() {
        db.write { tx in manager.save(ChatFolder(name: "A"), tx: tx) }
        let local = db.read { tx in manager.folders(tx: tx) }.first!
        let remote = ChatFolder(kind: .allChats, name: "", position: 0)
        db.write { tx in
            manager.applyRemote(remote, tx: tx)
            manager.deleteOtherAllChatsFolders(keeping: remote.id, tx: tx)
        }
        let allChats = db.read { tx in manager.folders(tx: tx) }.filter { $0.kind == .allChats }
        XCTAssertEqual(allChats.map(\.id), [remote.id])
        XCTAssertTrue(syncedIds.contains(local.id))
    }

    func testSuggestions() {
        let unread = ChatFolderManager.Suggestion.unread.makeFolder(name: "Unread")
        XCTAssertTrue(unread.showOnlyUnread)
        XCTAssertTrue(ChatFolderManager.Suggestion.unread.isAlreadyAdded(in: [unread]))
        XCTAssertFalse(ChatFolderManager.Suggestion.groups.isAlreadyAdded(in: [unread]))
    }
}
