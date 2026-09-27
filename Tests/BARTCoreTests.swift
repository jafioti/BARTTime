import XCTest
@testable import BARTTimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BARTCoreTests: XCTestCase {
    private let fixtureDate = Date(timeIntervalSince1970: 1790522537)

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "montgomery", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func response(estimates: [[String: Any]], date: String = "09/27/2026", time: String = "08:22:17 AM PDT") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["root": [
            "date": date, "time": time,
            "station": [["abbr": "MONT", "etd": [[
                "destination": "Antioch", "abbreviation": "ANTC", "estimate": estimates
            ]]]]
        ]])
    }

    private func estimate(_ minutes: Any = "5", color: String = "YELLOW", platform: String = "2", cancelled: String = "0") -> [String: Any] {
        ["minutes": minutes, "color": color, "platform": platform, "direction": "North",
         "length": "8", "delay": "240", "cancelflag": cancelled]
    }

    func testActualBARTResponseGroupsAllLinesAndDestinations() throws {
        let snapshot = try BARTDecoder.departures(from: fixture(), stationCode: "MONT", receivedAt: fixtureDate)
        XCTAssertEqual(snapshot.stationCode, "MONT")
        XCTAssertEqual(snapshot.departures.count, 16)
        XCTAssertEqual(snapshot.sections.map(\.line.code), ["YELLOW", "BLUE", "GREEN", "RED"])
        XCTAssertEqual(snapshot.sections[0].groups.count, 2)
        XCTAssertEqual(Set(snapshot.sections[0].groups.map(\.destination)), ["Antioch", "SF Airport"])
        XCTAssertEqual(snapshot.sourceDate, fixtureDate)
    }

    func testCancelledAndInvalidPredictionsAreExcludedAndTimesSorted() throws {
        let data = try response(estimates: [estimate("12"), estimate("3", cancelled: "1"),
                                            estimate("Leaving"), estimate("n/a"), estimate("-1"), estimate(5)])
        let snapshot = try BARTDecoder.departures(from: data, stationCode: "MONT", receivedAt: fixtureDate)
        let departures = try XCTUnwrap(snapshot.sections.first?.groups.first?.departures)
        XCTAssertEqual(departures.map(\.time), [.leaving, .minutes(5), .minutes(12)])
        XCTAssertEqual(departures.first?.cars, 8)
        XCTAssertEqual(departures.first?.delaySeconds, 240)
    }

    func testSameDestinationOnDifferentLinesAndPlatformsStaysSeparate() throws {
        let data = try response(estimates: [estimate(), estimate(color: "BLUE"), estimate(platform: "1")])
        let snapshot = try BARTDecoder.departures(from: data, stationCode: "MONT", receivedAt: fixtureDate)
        XCTAssertEqual(snapshot.sections.count, 2)
        XCTAssertEqual(snapshot.sections[0].groups.count, 2)
    }

    func testSingletonObjectsAndNumericFields() throws {
        let json = """
        {"root":{"date":"09/27/2026","time":"08:22:17 AM PDT","station":{
        "abbr":"MONT","etd":{"destination":"Antioch","abbreviation":"ANTC","estimate":{
        "minutes":3,"platform":2,"length":8,"color":"YELLOW","cancelflag":0,"delay":0}}}}}
        """
        let snapshot = try BARTDecoder.departures(from: Data(json.utf8), stationCode: "MONT", receivedAt: fixtureDate)
        XCTAssertEqual(snapshot.departures.first?.time, .minutes(3))
        XCTAssertEqual(snapshot.departures.first?.platform, "2")
    }

    func testEmptyPredictionsAreValid() throws {
        for empty in ["[]", "null", "\"\""] {
            let json = """
            {"root":{"date":"09/27/2026","time":"08:22:17 AM PDT","station":[{"abbr":"MONT","etd":\(empty)}]}}
            """
            let snapshot = try BARTDecoder.departures(from: Data(json.utf8), stationCode: "MONT", receivedAt: fixtureDate)
            XCTAssertTrue(snapshot.departures.isEmpty)
        }
    }

    func testAPIErrorDoesNotMasqueradeAsEmptyPredictions() throws {
        let data = Data("{\"root\":{\"message\":{\"error\":{\"text\":\"Invalid key\"}}}}".utf8)
        XCTAssertThrowsError(try BARTDecoder.departures(from: data, stationCode: "MONT")) {
            XCTAssertEqual($0 as? BARTError, .service("Invalid key"))
        }
    }

    func testWrongStationAndMalformedDataAreRejected() throws {
        XCTAssertThrowsError(try BARTDecoder.departures(from: fixture(), stationCode: "EMBR", receivedAt: fixtureDate)) {
            XCTAssertEqual($0 as? BARTError, .wrongStation)
        }
        XCTAssertThrowsError(try BARTDecoder.departures(from: Data("<html>Forbidden</html>".utf8), stationCode: "MONT"))
    }

    func testFreshnessUsesSourceTimestampNotFetchTime() throws {
        let snapshot = try BARTDecoder.departures(from: fixture(), stationCode: "MONT", receivedAt: fixtureDate.addingTimeInterval(3600))
        XCTAssertFalse(snapshot.isStale(at: fixtureDate.addingTimeInterval(119)))
        XCTAssertTrue(snapshot.isStale(at: fixtureDate.addingTimeInterval(121)))
        XCTAssertTrue(snapshot.isStale(at: snapshot.receivedAt))
    }

    func testFutureOrInvalidTimestampIsRejected() throws {
        XCTAssertThrowsError(try BARTDecoder.departures(from: fixture(), stationCode: "MONT", receivedAt: fixtureDate.addingTimeInterval(-600)))
        let data = try response(estimates: [estimate()], date: "invalid")
        XCTAssertThrowsError(try BARTDecoder.departures(from: data, stationCode: "MONT", receivedAt: fixtureDate))
    }

    func testPacificDaylightAndStandardTime() throws {
        let daylight = try XCTUnwrap(BARTDecoder.sourceDate(date: "09/27/2026", time: "08:22:17 AM PDT"))
        let standard = try XCTUnwrap(BARTDecoder.sourceDate(date: "09/27/2026", time: "08:22:17 AM PST"))
        XCTAssertEqual(standard.timeIntervalSince(daylight), 3600)
        XCTAssertEqual(BARTDecoder.sourceDate(date: "09/27/2026", time: "08:22:17 AM"), daylight)
    }

    func testBundledCatalogContainsAll50UniqueStationsAndSearchWorks() throws {
        let stations = try StationCatalog.bundled()
        XCTAssertEqual(stations.count, 50)
        XCTAssertEqual(Set(stations.map(\.id)).count, 50)
        let montgomery = try XCTUnwrap(stations.first { $0.id == "MONT" })
        XCTAssertTrue(montgomery.matches("  mont  "))
        XCTAssertTrue(montgomery.matches("san francisco"))
        XCTAssertFalse(montgomery.matches("Berkeley"))
        XCTAssertFalse(try XCTUnwrap(stations.first { $0.id == "OAKL" }).hasRealtime)
    }

    func testStationEnvelopeParsing() throws {
        let stationJSON = """
        {"root":{"stations":{"station":[{"name":"Montgomery St.","abbr":"MONT","city":"San Francisco","address":"598 Market St."}]}}}
        """
        let stations = try BARTDecoder.stations(from: Data(stationJSON.utf8))
        XCTAssertEqual(stations.first?.id, "MONT")
    }

    func testMissingAPIKeyFailsBeforeNetworkRequest() {
        XCTAssertThrowsError(try BARTClient(key: " ").request(path: "etd.aspx", parameters: ["cmd": "etd"])) { error in
            XCTAssertEqual(error as? BARTError, .service("BART API key is missing. Configure BART_API_KEY to load live data."))
        }
    }

    func testRequestUsesHTTPSAndEscapesParameters() throws {
        let request = try BARTClient(key: "a&b").request(path: "etd.aspx", parameters: ["cmd": "etd", "orig": "MONT"])
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.bart.gov")
        let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(parameters, ["cmd": "etd", "orig": "MONT", "key": "a&b", "json": "y"])
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.timeoutInterval, 20)
    }

    func testLeavingAndZeroAreUnderOneMinute() {
        XCTAssertEqual(DepartureTime(apiValue: " Leaving "), .leaving)
        XCTAssertEqual(DepartureTime(apiValue: "0"), .leaving)
        XCTAssertNil(DepartureTime(apiValue: "unknown"))
    }

    func testLiveFeedWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["BART_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set BART_LIVE_TEST=1 to query the real BART service.")
        }
        let service = BARTClient()
        let stations = try await service.stations()
        XCTAssertGreaterThanOrEqual(stations.count, 50)
        for station in ["MONT", "MCAR", "BERY"] {
            let snapshot = try await service.departures(at: station)
            XCTAssertEqual(snapshot.stationCode, station)
            XCTAssertLessThan(abs(snapshot.sourceDate.timeIntervalSinceNow), 300)
            print("Live \(station): \(snapshot.departures.count) estimates, \(snapshot.sections.count) lines")
        }
    }
}
