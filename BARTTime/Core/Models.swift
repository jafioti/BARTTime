import Foundation

public struct Station: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    public let abbr: String
    public let city: String
    public let address: String
    public var id: String { abbr }
    public var hasRealtime: Bool { abbr != "OAKL" }

    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [name, abbr, city].contains {
            $0.localizedStandardContains(query)
        }
    }
}

public struct RailLine: Hashable, Identifiable, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code.uppercased() }
    public var id: String { code }
    public var name: String { code == "" ? "Other service" : "\(code.capitalized) line" }
    public var sortOrder: Int {
        ["YELLOW", "BLUE", "GREEN", "RED", "ORANGE", "BEIGE"].firstIndex(of: code) ?? 99
    }
}

public enum DepartureTime: Equatable, Sendable {
    case minutes(Int)
    case leaving

    public init?(apiValue: String) {
        let value = apiValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased() == "leaving" {
            self = .leaving
        } else if let minutes = Int(value), minutes >= 0 {
            self = minutes == 0 ? .leaving : .minutes(minutes)
        } else {
            return nil
        }
    }

    public var sortValue: Int {
        switch self {
        case .minutes(let value): return value
        case .leaving: return 0
        }
    }
    public var label: String {
        switch self {
        case .minutes(let value): return "\(value)"
        case .leaving: return "Leaving"
        }
    }
    public var accessibilityLabel: String {
        switch self {
        case .minutes(let value): return "Estimated departure in \(value) \(value == 1 ? "minute" : "minutes")"
        case .leaving: return "Leaving in less than one minute"
        }
    }
}

public struct Departure: Identifiable, Sendable {
    public let id: String
    public let line: RailLine
    public let destination: String
    public let destinationCode: String
    public let direction: String
    public let platform: String
    public let time: DepartureTime
    public let cars: Int?
    public let delaySeconds: Int
}

public struct DepartureGroup: Identifiable, Sendable {
    public let id: String
    public let destination: String
    public let direction: String
    public let platform: String
    public let departures: [Departure]
}

public struct LineSection: Identifiable, Sendable {
    public let line: RailLine
    public let groups: [DepartureGroup]
    public var id: String { line.id }
}

public struct DepartureSnapshot: Sendable {
    public let stationCode: String
    public let sourceDate: Date
    public let receivedAt: Date
    public let departures: [Departure]

    public func isStale(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(sourceDate) > 120
    }

    public var sections: [LineSection] {
        let byLine = Dictionary(grouping: departures, by: \.line)
        return byLine.map { line, departures in
            let byDestination = Dictionary(grouping: departures) {
                "\($0.destinationCode)|\($0.direction)|\($0.platform)"
            }
            let groups = byDestination.map { key, departures in
                let sorted = departures.sorted {
                    if $0.time.sortValue != $1.time.sortValue { return $0.time.sortValue < $1.time.sortValue }
                    return $0.id < $1.id
                }
                let first = sorted[0]
                return DepartureGroup(id: key, destination: first.destination, direction: first.direction,
                                      platform: first.platform, departures: sorted)
            }.sorted {
                if $0.direction != $1.direction { return $0.direction < $1.direction }
                return $0.id < $1.id
            }
            return LineSection(line: line, groups: groups)
        }.sorted {
            if $0.line.sortOrder != $1.line.sortOrder { return $0.line.sortOrder < $1.line.sortOrder }
            return $0.line.code < $1.line.code
        }
    }
}

public enum StationCatalog {
    public static func bundled() throws -> [Station] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "stations", withExtension: "json") else {
            throw BARTError.invalidResponse
        }
        return try JSONDecoder().decode([Station].self, from: Data(contentsOf: url))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Scheduled stops are ordered in the direction of travel. Only timed stops count.
public struct ScheduledStop: Sendable {
    public let station: String
    public let minute: Int

    static func clockMinute(_ text: String) -> Int? {
        let parts = text.uppercased().split(separator: " ")
        guard parts.count == 2, ["AM", "PM"].contains(parts[1]) else { return nil }
        let clock = parts[0].split(separator: ":")
        guard clock.count == 2, let h = Int(clock[0]), let m = Int(clock[1]),
              (1...12).contains(h), (0...59).contains(m) else { return nil }
        return h % 12 * 60 + m + (parts[1] == "PM" ? 720 : 0)
    }
}

public struct RouteTimetable: Sendable {
    public let line: RailLine
    public let direction: String
    public let trains: [[ScheduledStop]]

    public static func decode(_ data: Data, line: RailLine, direction: String) throws -> RouteTimetable {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = json["root"] as? [String: Any],
              let route = root["route"] as? [String: Any] else { throw BARTError.invalidResponse }
        let rows = route["train"] as? [[String: Any]] ?? (route["train"] as? [String: Any]).map { [$0] } ?? []
        let trains = rows.map { row in
            (row["stop"] as? [[String: Any]] ?? []).compactMap { stop -> ScheduledStop? in
                guard let station = stop["@station"] as? String,
                      let time = stop["@origTime"] as? String,
                      let minute = ScheduledStop.clockMinute(time) else { return nil }
                return ScheduledStop(station: station, minute: minute)
            }
        }.filter { !$0.isEmpty }
        return RouteTimetable(line: line, direction: direction, trains: trains)
    }
}

public struct PinnedArrival: Identifiable, Sendable {
    public let station: Station
    public let minutes: Int
    public let date: Date
    public var id: String { station.id }
}

public enum ArrivalEstimator {
    public static func arrivals(for departure: Departure, origin: String, pins: [Station],
                                timetables: [RouteTimetable], sourceDate: Date) -> [PinnedArrival] {
        let trains = timetables.filter {
            $0.line == departure.line && (departure.direction.isEmpty || $0.direction == departure.direction)
        }.flatMap(\.trains).filter { $0.last?.station == departure.destinationCode }
        return pins.compactMap { pin in
            guard pin.id != origin else { return nil }
            let durations = trains.compactMap { stops -> Int? in
                guard let start = stops.firstIndex(where: { $0.station == origin }),
                      let end = stops.firstIndex(where: { $0.station == pin.id }), end > start else { return nil }
                let duration = (stops[end].minute - stops[start].minute + 1440) % 1440
                return duration > 0 && duration < 240 ? duration : nil
            }.sorted()
            guard !durations.isEmpty else { return nil }
            // Median schedule duration avoids pretending to identify a live train by timetable ID.
            let minutes = departure.time.sortValue + durations[durations.count / 2]
            return PinnedArrival(station: pin, minutes: minutes,
                                 date: sourceDate.addingTimeInterval(Double(minutes * 60)))
        }.sorted { $0.minutes == $1.minutes ? $0.station.name < $1.station.name : $0.minutes < $1.minutes }
    }
}
