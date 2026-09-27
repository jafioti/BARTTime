import XCTest
@testable import BARTTimeCore

private actor ScriptedService: BARTServing {
    private var results: [Result<DepartureSnapshot, BARTError>]
    private(set) var departureCalls = 0
    let delay: Duration

    init(results: [Result<DepartureSnapshot, BARTError>], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func stations() async throws -> [Station] { throw BARTError.http(503) }

    func departures(at stationCode: String) async throws -> DepartureSnapshot {
        departureCalls += 1
        if delay != .zero { try await Task.sleep(for: delay) }
        guard !results.isEmpty else { throw BARTError.http(503) }
        return try results.removeFirst().get()
    }
}

final class AppStateTests: XCTestCase {
    private func snapshot() throws -> DepartureSnapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "montgomery", withExtension: "json"))
        return try BARTDecoder.departures(from: Data(contentsOf: url), stationCode: "MONT")
    }

    @MainActor
    func testFailedRefreshKeepsLastGoodPredictionsThenRecovers() async throws {
        let data = try snapshot()
        let service = ScriptedService(results: [.success(data), .failure(.http(503)), .success(data)])
        let store = DepartureStore(service: service)
        await store.refresh(stationCode: "MONT")
        XCTAssertEqual(store.snapshot?.departures.count, 16)
        XCTAssertNil(store.error)
        await store.refresh(stationCode: "MONT")
        XCTAssertEqual(store.snapshot?.departures.count, 16)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.isLoading)
        await store.refresh(stationCode: "MONT")
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testInitialFailureHasAnErrorAndNoFakePredictions() async {
        let store = DepartureStore(service: ScriptedService(results: [.failure(.http(403))]))
        await store.refresh(stationCode: "MONT")
        XCTAssertNil(store.snapshot)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testBundledStationsRemainUsableWhenNetworkFails() async {
        let store = StationStore(service: ScriptedService(results: []))
        XCTAssertEqual(store.stations.count, 50)
        await store.refresh()
        XCTAssertEqual(store.stations.count, 50)
        XCTAssertNotNil(store.error)
    }

    @MainActor
    func testConcurrentRefreshesDoNotDuplicateNetworkRequests() async throws {
        let service = ScriptedService(results: [.success(try snapshot())], delay: .milliseconds(50))
        let store = DepartureStore(service: service)
        async let first: Void = store.refresh(stationCode: "MONT")
        async let second: Void = store.refresh(stationCode: "MONT")
        _ = await (first, second)
        let calls = await service.departureCalls
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(store.snapshot)
    }

    @MainActor
    func testCancellationDoesNotPublishErrorOrOldResponse() async throws {
        let service = ScriptedService(results: [.success(try snapshot())], delay: .milliseconds(200))
        let store = DepartureStore(service: service)
        let task = Task { await store.refresh(stationCode: "MONT") }
        while !store.isLoading { await Task.yield() }
        task.cancel()
        await task.value
        XCTAssertNil(store.error)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testMonitorStopsWhenViewTaskIsCancelled() async throws {
        let service = ScriptedService(results: [.success(try snapshot())])
        let store = DepartureStore(service: service)
        let task = Task { await store.monitor(stationCode: "MONT") }
        while store.snapshot == nil { await Task.yield() }
        task.cancel()
        await task.value
        let calls = await service.departureCalls
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.error)
    }
}
