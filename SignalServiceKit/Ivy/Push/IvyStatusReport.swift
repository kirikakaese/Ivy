//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation

/// Everything Ivy Status reports (relay/gateway/public.go), for the status
/// screen. The last report that arrived is kept, so the screen can show it
/// when the relay can't be reached.
public struct IvyStatusReport: Codable, Equatable, Sendable {

    public struct Minutes: Codable, Equatable, Sendable {
        public var ok: Int
        public var maintenance: Int
        public var degraded: Int
        public var down: Int

        public var total: Int { ok + maintenance + degraded + down }
    }

    /// An hour of a day (UTC) with minutes that weren't fine.
    public struct Hour: Codable, Equatable, Sendable {
        public var hour: Int
        public var maintenance: Int?
        public var degraded: Int?
        public var down: Int?
    }

    public struct Day: Codable, Equatable, Sendable {
        /// The day in UTC, as yyyy-MM-dd.
        public var date: String
        /// ok, maintenance, degraded, down or none.
        public var status: String
        public var minutes: Minutes?
        public var hours: [Hour]?
    }

    public struct Component: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var description: String
        public var status: String
        public var detail: String?
        public var days: [Day]?
    }

    public struct Metrics: Codable, Equatable, Sendable {
        public var uptime30: Double?
        public var uptime90: Double?
        public var wakeMedianMs: Double?
        public var acceptance24h: Double?
    }

    public struct Update: Codable, Equatable, Sendable {
        public var time: Date
        public var step: String
        public var message: String
    }

    public struct Post: Codable, Equatable, Sendable {
        public var id: String
        public var kind: String
        public var title: String
        public var impact: String?
        /// The affected services, by name.
        public var components: [String]?
        public var starts: Date?
        public var ends: Date?
        public var created: Date
        public var closed: Date?
        public var updates: [Update]?
    }

    /// ok, maintenance, degraded, down or unknown.
    public var status: String
    public var checked: Date?
    public var components: [Component]
    public var metrics: Metrics?
    public var active: [Post]?
    public var upcoming: [Post]?
    public var recent: [Post]?

    // MARK: - Decoding

    /// The gateway writes times with nanoseconds, which ISO8601DateFormatter
    /// doesn't read; the fraction is dropped.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(text)"))
            }
            return date
        }
        return decoder
    }()

    public static func parseDate(_ text: String) -> Date? {
        let withoutFraction = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: withoutFraction)
    }

    public static func decode(_ data: Data) throws -> IvyStatusReport {
        try decoder.decode(IvyStatusReport.self, from: data)
    }

    // MARK: - Fetching

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The status data from the relay; a report that arrives is kept.
    static func fetchData(relayURL: URL) async throws -> Data {
        let (data, response) = try await session.data(from: IvyServiceStatus.reportURL(for: relayURL))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        if (try? decode(data)) != nil {
            Saved.store(data)
        }
        return data
    }

    public static func fetch(relayURL: URL) async throws -> IvyStatusReport {
        try decode(try await fetchData(relayURL: relayURL))
    }

    // MARK: - The last report

    /// The last report that arrived and when, in the app group, so the
    /// status screen has something to show when the relay doesn't answer.
    public enum Saved {
        private static let dataKey = "IvyStatusReportData"
        private static let dateKey = "IvyStatusReportDate"

        static func store(_ data: Data, at date: Date = Date(), defaults: UserDefaults = CurrentAppContext().appUserDefaults()) {
            defaults.set(data, forKey: dataKey)
            defaults.set(date, forKey: dateKey)
        }

        public static func load(defaults: UserDefaults = CurrentAppContext().appUserDefaults()) -> (report: IvyStatusReport, received: Date)? {
            guard
                let data = defaults.data(forKey: dataKey),
                let date = defaults.object(forKey: dateKey) as? Date,
                let report = try? decode(data)
            else {
                return nil
            }
            return (report, date)
        }
    }
}
