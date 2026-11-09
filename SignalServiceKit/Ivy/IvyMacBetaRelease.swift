//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A Mac beta on the releases page ("Ivy Mac beta N", tag `mac-beta-N`),
/// for the beta's updater.
public struct IvyMacBetaRelease: Equatable, Sendable {
    public let number: Int
    public let zipURL: URL
    /// The SHA-256 of the zip, from the release notes.
    public let sha256: String
    /// What changed since the beta before, from the release notes.
    public var changes: [String] = []

    public static let assetName = "Ivy-Mac-Beta.zip"
    public static let releasesURL = URL(string: "https://api.github.com/repos/kirikakaese/Ivy/releases?per_page=20")!
    public static let releasesPageURL = URL(string: "https://github.com/kirikakaese/Ivy/releases")!

    /// The newest beta in a GitHub releases listing, or nil.
    public static func newest(inReleasesJSON data: Data) -> IvyMacBetaRelease? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let body: String?
            let draft: Bool
            let assets: [Asset]
        }
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else {
            return nil
        }
        return releases.compactMap { release -> IvyMacBetaRelease? in
            guard
                !release.draft,
                release.tag_name.hasPrefix("mac-beta-"),
                let number = Int(release.tag_name.dropFirst("mac-beta-".count)),
                let asset = release.assets.first(where: { $0.name == assetName }),
                let sha256 = sha256(inNotes: release.body ?? "")
            else {
                return nil
            }
            var result = IvyMacBetaRelease(number: number, zipURL: asset.browser_download_url, sha256: sha256)
            result.changes = changes(inNotes: release.body ?? "")
            return result
        }.max { $0.number < $1.number }
    }

    /// The checksum line of the release notes ("SHA-256: …").
    static func sha256(inNotes notes: String) -> String? {
        guard let range = notes.range(of: #"SHA-256:\s*([0-9a-f]{64})"#, options: .regularExpression) else {
            return nil
        }
        return String(notes[range].suffix(64))
    }

    /// The lines of the "Changes:" list in the release notes.
    static func changes(inNotes notes: String) -> [String] {
        var lines = notes.components(separatedBy: .newlines).makeIterator()
        while let line = lines.next() {
            if line.trimmingCharacters(in: .whitespaces) == "Changes:" {
                break
            }
        }
        var changes: [String] = []
        while let line = lines.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else {
                break
            }
            changes.append(String(trimmed.dropFirst(2)))
        }
        return changes
    }

    /// This beta's number, written into its Info.plist when it is built;
    /// nil outside the beta or for a beta built by hand.
    public static var currentNumber: Int? {
        (Bundle.main.object(forInfoDictionaryKey: "IvyMacBetaNumber") as? String).flatMap(Int.init)
    }
}
