import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol BARTServing: Sendable {
    func stations() async throws -> [Station]
    func departures(at stationCode: String) async throws -> DepartureSnapshot
}

public struct BARTClient: BARTServing, Sendable {
    public static var configuredKey: String {
        ProcessInfo.processInfo.environment["BART_API_KEY"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "BARTAPIKey") as? String)
            ?? ""
    }
    private let key: String
    private let session: URLSession

    public init(key: String = BARTClient.configuredKey, session: URLSession = .shared) {
        self.key = key
        self.session = session
    }

    public func stations() async throws -> [Station] {
        let data = try await fetch(path: "stn.aspx", parameters: ["cmd": "stns"])
        return try BARTDecoder.stations(from: data)
    }

    public func departures(at stationCode: String) async throws -> DepartureSnapshot {
        let data = try await fetch(path: "etd.aspx", parameters: ["cmd": "etd", "orig": stationCode])
        return try BARTDecoder.departures(from: data, stationCode: stationCode)
    }

    public func timetables(at stationCode: String) async throws -> [RouteTimetable] {
        let data = try await fetch(path: "route.aspx", parameters: ["cmd": "routeinfo", "route": "all"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = json["root"] as? [String: Any],
              let routes = root["routes"] as? [String: Any],
              let rows = routes["route"] as? [[String: Any]] else { throw BARTError.invalidResponse }
        let specs: [(String, String, String)] = rows.compactMap { row in
            guard let number = row["number"] as? String, let color = row["color"] as? String,
                  let direction = row["direction"] as? String,
                  let config = row["config"] as? [String: Any],
                  let stations = config["station"] as? [String], !stations.isEmpty, color != "GREY" else { return nil }
            return (number, color, direction)
        }
        return try await withThrowingTaskGroup(of: RouteTimetable.self) { group in
            for (number, color, direction) in specs {
                group.addTask {
                    let data = try await fetch(path: "sched.aspx", parameters: ["cmd": "routesched", "route": number, "date": "today"])
                    return try RouteTimetable.decode(data, line: RailLine(color), direction: direction)
                }
            }
            var result: [RouteTimetable] = []
            for try await timetable in group { result.append(timetable) }
            return result
        }
    }

    public func request(path: String, parameters: [String: String]) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BARTError.service("BART API key is missing. Configure BART_API_KEY to load live data.")
        }
        var components = URLComponents(string: "https://api.bart.gov/api/\(path)")!
        var parameters = parameters
        parameters["key"] = key
        parameters["json"] = "y"
        components.queryItems = parameters.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components.url else { throw BARTError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch(path: String, parameters: [String: String]) async throws -> Data {
        let request = try request(path: path, parameters: parameters)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw BARTError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw BARTError.http(response.statusCode) }
        return data
    }
}
