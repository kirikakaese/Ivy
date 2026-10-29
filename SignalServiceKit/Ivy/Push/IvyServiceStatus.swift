//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation

/// What Ivy Status reports (relay/gateway/public.go), reduced to what the
/// chat list shows: nothing, a notice, or a problem.
public struct IvyServiceStatus: Equatable, Sendable {

    public enum Level: Equatable, Sendable {
        case notice
        case maintenance
        case degraded
        case down
        /// Ivy couldn't reach the relay while the device was online.
        case unreachable
    }

    public var level: Level
    /// A post's own title, as written on the admin page; nil uses Ivy's
    /// text for the level.
    public var title: String?
    /// The latest update of a post.
    public var detail: String?
    /// The affected services, as the status page names them.
    public var components: [String]
    /// Stays the same while it's the same problem, so a collapsed banner
    /// stays collapsed.
    public var id: String

    /// Problems show on the profile picture; notices only in the chat list.
    public var isProblem: Bool { level != .notice }

    public static let unreachable = IvyServiceStatus(level: .unreachable, title: nil, detail: nil, components: [], id: "unreachable")

    // MARK: - Report

    struct Report: Decodable {
        struct Component: Decodable {
            var name: String
            var status: String
        }

        struct Update: Decodable {
            var message: String
        }

        struct Post: Decodable {
            var id: String
            var kind: String
            var title: String
            var impact: String?
            var components: [String]?
            var updates: [Update]?
        }

        var status: String
        var components: [Component]?
        var active: [Post]?
    }

    /// The status a report calls for: an incident first, then a problem the
    /// relay found by itself, then maintenance, then a notice.
    static func from(_ report: Report) -> IvyServiceStatus? {
        let posts = report.active ?? []
        let incidents = posts.filter { $0.kind == "incident" }
        if let incident = incidents.first(where: { $0.impact == "major" }) ?? incidents.first {
            return status(for: incident, level: incident.impact == "major" ? .down : .degraded)
        }
        let affected = (report.components ?? []).filter { $0.status != "ok" && $0.status != "unknown" }.map(\.name)
        switch report.status {
        case "down":
            return IvyServiceStatus(level: .down, title: nil, detail: nil, components: affected, id: "status.down")
        case "degraded":
            return IvyServiceStatus(level: .degraded, title: nil, detail: nil, components: affected, id: "status.degraded")
        default:
            break
        }
        if let maintenance = posts.first(where: { $0.kind == "maintenance" }) {
            return status(for: maintenance, level: .maintenance)
        }
        if report.status == "maintenance" {
            return IvyServiceStatus(level: .maintenance, title: nil, detail: nil, components: affected, id: "status.maintenance")
        }
        if let notice = posts.first(where: { $0.kind == "notice" }) {
            return status(for: notice, level: .notice)
        }
        return nil
    }

    private static func status(for post: Report.Post, level: Level) -> IvyServiceStatus {
        let detail = post.updates?.last?.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return IvyServiceStatus(
            level: level,
            title: post.title,
            detail: detail?.isEmpty == false ? detail : nil,
            components: post.components ?? [],
            id: "post." + post.id,
        )
    }

    // MARK: - Fetching

    /// The status page's data: the relay forwards it from Ivy Status.
    public static func reportURL(for relayURL: URL) -> URL {
        return IvyPushRelay.statusPageURL(for: relayURL).appendingPathComponent("status.json")
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Asks the relay how Ivy is doing; nil when all is well.
    public static func fetch(relayURL: URL) async throws -> IvyServiceStatus? {
        let (data, response) = try await session.data(from: reportURL(for: relayURL))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return from(try JSONDecoder().decode(Report.self, from: data))
    }
}
