//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

// Apple Focus: a Focus can name chat folders; while it is on, only chats in
// those folders notify.

@available(iOS 17, *)
struct IvyFolderEntity: AppEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("INTENT_FOLDER_TYPE", defaultValue: "Chat Folder", table: "Ivy"),
    )
    static let defaultQuery = IvyFolderQuery()

    /// The folder's id, as hex.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17, *)
struct IvyFolderQuery: EntityQuery {

    func entities(for identifiers: [IvyFolderEntity.ID]) async throws -> [IvyFolderEntity] {
        try await allFolders().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [IvyFolderEntity] {
        try await allFolders()
    }

    @MainActor
    private func allFolders() async throws -> [IvyFolderEntity] {
        try await IvyShortcuts.waitUntilReady()
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            ChatFolderManager.shared.folders(tx: tx)
                .filter { $0.kind == .custom }
                .map { IvyFolderEntity(id: $0.id.hexadecimalString, name: $0.name) }
        }
    }
}

@available(iOS 17, *)
struct IvyFocusFilter: SetFocusFilterIntent {

    static let title = LocalizedStringResource("INTENT_FOCUS_TITLE", defaultValue: "Set Chat Folders", table: "Ivy")
    static let description = IntentDescription(LocalizedStringResource(
        "INTENT_FOCUS_DESCRIPTION",
        defaultValue: "While this Focus is on, only chats in these folders notify.",
        table: "Ivy",
    ))

    @Parameter(title: LocalizedStringResource("INTENT_FOCUS_FOLDERS", defaultValue: "Folders", table: "Ivy"))
    var folders: [IvyFolderEntity]?

    var displayRepresentation: DisplayRepresentation {
        let names = (folders ?? []).map(\.name)
        guard !names.isEmpty else {
            return DisplayRepresentation(title: Self.title)
        }
        return DisplayRepresentation(title: Self.title, subtitle: "\(ListFormatter.localizedString(byJoining: names))")
    }

    func perform() async throws -> some IntentResult {
        // The Focus ending sets no folders.
        let ids = Set((folders ?? []).compactMap { Data(hex: $0.id) })
        IvyNotificationFocus.setFocusFolderIds(ids.isEmpty ? nil : ids)
        return .result()
    }
}
