import Foundation
import Observation

@MainActor @Observable
final class StationStore {
    private(set) var stations: [Station] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private let service: any BARTServing

    init(service: any BARTServing = BARTClient()) {
        self.service = service
        do { stations = try StationCatalog.bundled() }
        catch { self.error = "Couldn’t load the station list. Pull down to try again." }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let stations = try await service.stations()
            try Task.checkCancellation()
            self.stations = stations
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = stations.isEmpty
                ? "Couldn’t load stations. Check your connection and try again."
                : "Station list couldn’t refresh. Showing saved stations; live times load when you open one."
        }
    }
}

@MainActor @Observable
final class DepartureStore {
    private(set) var snapshot: DepartureSnapshot?
    private(set) var isLoading = false
    private(set) var error: String?
    private let service: any BARTServing

    init(service: any BARTServing = BARTClient()) { self.service = service }

    func refresh(stationCode: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let update = try await service.departures(at: stationCode)
            try Task.checkCancellation()
            snapshot = update
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            if let error = error as? BARTError {
                self.error = error.localizedDescription
            } else if let error = error as? URLError, error.code == .notConnectedToInternet {
                self.error = "You’re offline. Reconnect to get live train times."
            } else {
                self.error = "Couldn’t refresh train times. Check your connection and try again."
            }
        }
    }

    func monitor(stationCode: String) async {
        while !Task.isCancelled {
            await refresh(stationCode: stationCode)
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
        }
    }
}
