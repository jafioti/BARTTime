import SwiftUI

@MainActor
struct StationDetailView: View {
    let station: Station
    @AppStorage private var directionFilter: String

    init(station: Station) {
        self.station = station
        _directionFilter = AppStorage(wrappedValue: "All", "stationDirection.\(station.id)")
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var store = DepartureStore()
    @AppStorage("favoriteStationCodes") private var favoriteCodes = ""
    @State private var timetables: [RouteTimetable] = []
    @State private var timetableError: String?
    @State private var loadingTimetables = false
    private var pins: [Station] {
        let codes = Set(favoriteCodes.split(separator: "|").map(String.init))
        return ((try? StationCatalog.bundled()) ?? []).filter { codes.contains($0.id) }
    }
    private var isPinned: Bool { pins.contains { $0.id == station.id } }
    private func togglePin() {
        var codes = Set(favoriteCodes.split(separator: "|").map(String.init))
        if isPinned { codes.remove(station.id) } else { codes.insert(station.id) }
        favoriteCodes = codes.sorted().joined(separator: "|")
    }
    private func loadTimetables() async {
        guard pins.contains(where: { $0.id != station.id }), station.hasRealtime else { return }
        loadingTimetables = true
        defer { loadingTimetables = false }
        do {
            let result = try await BARTClient().timetables(at: station.id)
            try Task.checkCancellation()
            timetables = result
            timetableError = nil
        } catch {
            guard !Task.isCancelled else { return }
            timetables = []
            timetableError = "Pinned arrival estimates are unavailable. Tap to retry."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stationHeader
                if !station.hasRealtime {
                    ContentUnavailableView {
                        Label("Airport connector", systemImage: "airplane")
                    } description: {
                        Text("BART doesn’t publish live predictions for the Oakland Airport Connector.")
                    } actions: {
                        Link("View BART service information ↗", destination: URL(string: "https://www.bart.gov/guide/airport/oak")!)
                    }
                } else {
                    Picker("Direction", selection: $directionFilter) {
                        Text("All").tag("All")
                        Text("Northbound").tag("North")
                        Text("Southbound").tag("South")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Saved automatically for this station")
                    departuresContent
                }
                BARTAttribution()
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color.railBackground)
        .navigationTitle("Next trains")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: togglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(isPinned ? "Unpin station" : "Pin station")
            }
            if station.hasRealtime {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh(stationCode: station.id) }
                    } label: {
                        if store.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.isLoading)
                    .accessibilityLabel("Refresh train times")
                }
            }
        }
        .refreshable {
            if station.hasRealtime { await store.refresh(stationCode: station.id) }
        }
        .task(id: "\(scenePhase)-\(favoriteCodes)") {
            guard scenePhase == .active else { return }
            await loadTimetables()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, station.hasRealtime else { return }
            await store.monitor(stationCode: station.id)
        }
    }

    private var stationHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                Text(station.city.uppercased()).tracking(1.5)
                Spacer()
                Text(station.abbr)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.railAccent.opacity(0.08), in: Capsule())
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Color.railAccent)
            Text(station.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(station.address).font(.subheadline).foregroundStyle(.secondary)
            RailStripes().padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var departuresContent: some View {
        if let snapshot = store.snapshot {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let stale = snapshot.isStale(at: context.date) || store.error != nil
                let departures = snapshot.departures.filter {
                    directionFilter == "All" || $0.direction.caseInsensitiveCompare(directionFilter) == .orderedSame
                }.sorted {
                    $0.time.sortValue == $1.time.sortValue
                        ? $0.id < $1.id : $0.time.sortValue < $1.time.sortValue
                }
                VStack(alignment: .leading, spacing: 20) {
                    freshness(snapshot, stale: stale)
                    if let error = store.error {
                        NoticeView(text: "\(error) These are the last known estimates.")
                    } else if stale {
                        NoticeView(text: "BART’s latest update is over two minutes old. These times may have changed.", symbol: "clock.badge.exclamationmark")
                    }

                    if loadingTimetables {
                        ProgressView("Loading pinned arrival estimates…").font(.caption)
                    } else if let timetableError {
                        Button(timetableError) { Task { await loadTimetables() } }
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if pins.contains(where: { $0.id != station.id }) {
                        Text("Pinned arrivals are approximate: live departure estimate + scheduled travel time. Only stops ahead on this train’s route are shown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if snapshot.departures.isEmpty {
                        ContentUnavailableView {
                            Label("No predictions right now", systemImage: "tram")
                        } description: {
                            Text("BART has no upcoming train estimates for this station. Service may be finished or predictions temporarily unavailable.")
                        }
                    } else if departures.isEmpty {
                        ContentUnavailableView {
                            Label("No \(directionFilter.lowercased())bound trains", systemImage: "tram")
                        } description: {
                            Text("There are no predictions in your saved direction right now.")
                        } actions: {
                            Button("Show all directions") { directionFilter = "All" }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        ForEach(departures) { departure in
                            TrainCard(departure: departure, isStale: stale, origin: station.id,
                                     pins: pins, timetables: timetables, sourceDate: snapshot.sourceDate,
                                     arrivalsAvailable: !loadingTimetables && timetableError == nil)
                        }
                    }

                    Text("Times are BART’s estimated departures, in minutes. “Leaving” means less than a minute until departure. Updates automatically every 30 seconds.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let error = store.error {
            ContentUnavailableView {
                Label("Can’t load train times", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await store.refresh(stationCode: station.id) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading)
            }
        } else {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Finding your next train…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 70)
        }
    }

    private func freshness(_ snapshot: DepartureSnapshot, stale: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                statusBadge(stale: stale)
                Spacer()
                timestamp(snapshot)
            }
            VStack(alignment: .leading, spacing: 8) {
                statusBadge(stale: stale)
                timestamp(snapshot)
            }
        }
    }

    private func statusBadge(stale: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(stale ? Color.orange : Color.railAccent).frame(width: 6, height: 6)
            Text(stale ? "LAST KNOWN TIMES" : "LIVE PREDICTIONS").tracking(1)
        }
        .font(.caption2.weight(.bold)).foregroundStyle(stale ? Color.orange : Color.railAccent)
        .fixedSize()
    }

    private func timestamp(_ snapshot: DepartureSnapshot) -> some View {
        Text("Updated \(snapshot.sourceDate.formatted(date: .omitted, time: .shortened))")
            .font(.caption).foregroundStyle(.secondary)
    }
}
