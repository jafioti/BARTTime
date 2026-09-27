import XCTest
@testable import BARTTimeCore

final class ArrivalEstimatorTests: XCTestCase {
    private let source = Date(timeIntervalSince1970: 1_790_000_000)
    private func station(_ id: String) -> Station {
        Station(name: id, abbr: id, city: "", address: "")
    }
    private func departure(destination: String = "C", time: DepartureTime = .minutes(5),
                           line: String = "YELLOW", direction: String = "North") -> Departure {
        Departure(id: "train", line: RailLine(line), destination: destination, destinationCode: destination,
                  direction: direction, platform: "1", time: time, cars: 8, delaySeconds: 240)
    }
    private var table: RouteTimetable {
        RouteTimetable(line: RailLine("YELLOW"), direction: "North", trains: [
            [ScheduledStop(station: "A", minute: 1435), ScheduledStop(station: "B", minute: 5),
             ScheduledStop(station: "C", minute: 12)]
        ])
    }
    func testDownstreamOnlyAndMidnightDurationIncludesWaitButNotDelayAgain() {
        let results = ArrivalEstimator.arrivals(for: departure(), origin: "A",
            pins: [station("C"), station("B"), station("A"), station("X")], timetables: [table], sourceDate: source)
        XCTAssertEqual(results.map(\.id), ["B", "C"])
        XCTAssertEqual(results.map(\.minutes), [15, 22])
        XCTAssertEqual(results[0].date, source.addingTimeInterval(900))
        let reverse = ArrivalEstimator.arrivals(for: departure(), origin: "B", pins: [station("A")],
            timetables: [table], sourceDate: source)
        XCTAssertTrue(reverse.isEmpty)
    }
    func testWrongLineDirectionAndShortTurnDoNotLeakStops() {
        for train in [departure(line: "RED"), departure(direction: "South"), departure(destination: "B")] {
            XCTAssertTrue(ArrivalEstimator.arrivals(for: train, origin: "A", pins: [station("C")],
                timetables: [table], sourceDate: source).isEmpty)
        }
    }
    func testLeavingAndMedianScheduleDuration() {
        let second = RouteTimetable(line: RailLine("YELLOW"), direction: "North", trains: [
            [ScheduledStop(station: "A", minute: 10), ScheduledStop(station: "B", minute: 22), ScheduledStop(station: "C", minute: 30)],
            [ScheduledStop(station: "A", minute: 10), ScheduledStop(station: "B", minute: 21), ScheduledStop(station: "C", minute: 30)]
        ])
        let result = ArrivalEstimator.arrivals(for: departure(time: .leaving), origin: "A", pins: [station("B")],
            timetables: [table, second], sourceDate: source)
        XCTAssertEqual(result.first?.minutes, 11)
    }
    func testLiveTimetableIntegration() async throws {
        guard ProcessInfo.processInfo.environment["BART_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set BART_LIVE_TEST=1 to check live schedules")
        }
        let tables = try await BARTClient().timetables(at: "MONT")
        XCTAssertFalse(tables.isEmpty)
        let train = Departure(id: "sample", line: RailLine("YELLOW"), destination: "SF Airport",
                              destinationCode: "SFIA", direction: "South", platform: "1",
                              time: .minutes(5), cars: 8, delaySeconds: 0)
        let result = ArrivalEstimator.arrivals(for: train, origin: "MONT", pins: [station("DALY"), station("SFIA"), station("RICH")],
                                              timetables: tables, sourceDate: source)
        XCTAssertEqual(result.map(\.id), ["DALY", "SFIA"])
        XCTAssertTrue(result.allSatisfy { $0.minutes > 5 && $0.minutes < 90 })
    }

    func testDecodingIgnoresUntimedStopsAndHandlesSingletonTrain() throws {
        let data = Data(#"{"root":{"route":{"train":{"stop":[{"@station":"X"},{"@station":"A","@origTime":"11:55 PM"},{"@station":"C","@origTime":"12:12 AM"}]}}}}"#.utf8)
        let result = try RouteTimetable.decode(data, line: RailLine("YELLOW"), direction: "North")
        XCTAssertEqual(result.trains.first?.map(\.station), ["A", "C"])
        XCTAssertEqual(result.trains.first?.map(\.minute), [1435, 12])
        XCTAssertNil(ScheduledStop.clockMinute("25:99 PM"))
        XCTAssertThrowsError(try RouteTimetable.decode(Data("{}".utf8), line: RailLine("YELLOW"), direction: "North"))
    }
}
