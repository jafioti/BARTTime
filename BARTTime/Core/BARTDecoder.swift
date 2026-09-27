import Foundation

public enum BARTError: Error, LocalizedError, Equatable {
    case http(Int)
    case service(String)
    case invalidResponse
    case wrongStation

    public var errorDescription: String? {
        switch self {
        case .http(403), .http(401):
            return "BART isn’t accepting this request right now. Please try again shortly."
        case .http:
            return "BART’s live feed is temporarily unavailable. Please try again."
        case .service(let message): return message
        case .invalidResponse: return "BART returned an unreadable update. Please try again."
        case .wrongStation: return "BART didn’t return predictions for this station. Please try again."
        }
    }
}

public enum BARTDecoder {
    public static func stations(from data: Data) throws -> [Station] {
        try checkAPIError(data)
        let result = try JSONDecoder().decode(StationEnvelope.self, from: data)
        guard !result.root.stations.station.values.isEmpty else { throw BARTError.invalidResponse }
        return result.root.stations.station.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func departures(from data: Data, stationCode: String, receivedAt: Date = Date()) throws -> DepartureSnapshot {
        try checkAPIError(data)
        let result = try JSONDecoder().decode(DepartureEnvelope.self, from: data)
        guard let station = result.root.station.values.first(where: {
            $0.abbr.uppercased() == stationCode.uppercased()
        }) else { throw BARTError.wrongStation }
        guard let date = sourceDate(date: result.root.date, time: result.root.time),
              date.timeIntervalSince(receivedAt) < 300 else { throw BARTError.invalidResponse }

        var departures: [Departure] = []
        for (destinationIndex, destination) in station.etd.values.enumerated() {
            for (index, estimate) in destination.estimate.values.enumerated() {
                guard estimate.cancelflag?.value != "1",
                      let time = DepartureTime(apiValue: estimate.minutes.value) else { continue }
                departures.append(Departure(
                    id: "\(station.abbr)|\(destinationIndex)|\(index)",
                    line: RailLine(estimate.color), destination: destination.destination,
                    destinationCode: destination.abbreviation, direction: estimate.direction ?? "",
                    platform: estimate.platform?.value ?? "", time: time,
                    cars: estimate.length.flatMap { Int($0.value) },
                    delaySeconds: max(0, Int(estimate.delay?.value ?? "0") ?? 0)
                ))
            }
        }
        return DepartureSnapshot(stationCode: station.abbr, sourceDate: date,
                                 receivedAt: receivedAt, departures: departures)
    }

    /// BART timestamps are Pacific local time, regardless of the device's timezone.
    public static func sourceDate(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        if time.hasSuffix(" PDT") || time.hasSuffix(" PST") {
            formatter.timeZone = TimeZone(secondsFromGMT: time.hasSuffix(" PDT") ? -7 * 3600 : -8 * 3600)
            formatter.dateFormat = "MM/dd/yyyy hh:mm:ss a"
            return formatter.date(from: "\(date) \(time.dropLast(4))")
        }
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "MM/dd/yyyy hh:mm:ss a"
        return formatter.date(from: "\(date) \(time)")
    }

    private static func checkAPIError(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = object["root"] as? [String: Any] else { throw BARTError.invalidResponse }
        let message = root["message"] as? [String: Any]
        if let error = root["error"] ?? message?["error"] {
            let value = error as? [String: Any]
            let text = value?["text"] as? String ?? error as? String
            throw BARTError.service(text ?? "BART is unable to provide predictions right now.")
        }
    }
}

// The legacy XML-to-JSON feed sometimes serializes one item as an object and no items as "".
private struct FeedList<Element: Decodable>: Decodable {
    let values: [Element]
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { values = []; return }
        if let text = try? container.decode(String.self), text.isEmpty { values = []; return }
        if let array = try? container.decode([Element].self) { values = array; return }
        values = [try container.decode(Element.self)]
    }
    init() { values = [] }
}

private struct FeedScalar: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string }
        else { value = String(try container.decode(Int.self)) }
    }
}

private struct StationEnvelope: Decodable {
    let root: Root
    struct Root: Decodable {
        let stations: Stations
    }
    struct Stations: Decodable {
        let station: FeedList<Station>
    }
}

private struct DepartureEnvelope: Decodable {
    let root: Root
    struct Root: Decodable {
        let date: String
        let time: String
        let station: FeedList<FeedStation>
    }
    struct FeedStation: Decodable {
        let abbr: String
        let etd: FeedList<Destination>
        enum CodingKeys: String, CodingKey { case abbr, etd }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            abbr = try container.decode(String.self, forKey: .abbr)
            etd = try container.decodeIfPresent(FeedList<Destination>.self, forKey: .etd) ?? FeedList()
        }
    }
    struct Destination: Decodable {
        let destination: String
        let abbreviation: String
        let estimate: FeedList<Estimate>
    }
    struct Estimate: Decodable {
        let minutes: FeedScalar
        let platform: FeedScalar?
        let direction: String?
        let length: FeedScalar?
        let color: String
        let delay: FeedScalar?
        let cancelflag: FeedScalar?
    }
}
