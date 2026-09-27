import SwiftUI

@MainActor
struct StationListView: View {
    @State private var store = StationStore()
    @State private var query = ""
    @AppStorage("favoriteStationCodes") private var favoriteCodes = ""

    private var favorites: Set<String> { Set(favoriteCodes.split(separator: "|").map(String.init)) }
    private var filtered: [Station] { store.stations.filter { $0.matches(query) } }
    private var saved: [Station] { filtered.filter { favorites.contains($0.id) } }
    private var others: [Station] { filtered.filter { !favorites.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    NoticeView(text: error)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !saved.isEmpty {
                    Section("Pinned stations") {
                        ForEach(saved) { station in stationRow(station) }
                    }
                }
                if !others.isEmpty {
                    Section {
                        ForEach(others) { station in stationRow(station) }
                    } header: {
                        HStack {
                            Text(saved.isEmpty ? "All stations" : "More stations")
                            Spacer()
                            Text("\(others.count)")
                        }
                    }
                }

                if filtered.isEmpty {
                    if !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    } else if store.isLoading {
                        ProgressView("Loading stations…").frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView {
                            Label("Stations unavailable", systemImage: "tram")
                        } description: {
                            Text("Check your connection and pull down to refresh.")
                        } actions: {
                            Button("Try again") { Task { await store.refresh() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                BARTAttribution()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.railBackground)
            .navigationTitle("Stations")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station or city")
            .navigationDestination(for: Station.self) { station in
                StationDetailView(station: station)
            }
            .safeAreaInset(edge: .bottom) {
                if saved.isEmpty {
                    Text("Swipe a station to pin it to the top.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(10).frame(maxWidth: .infinity).background(.bar)
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }

    private func stationRow(_ station: Station) -> some View {
        NavigationLink(value: station) {
            HStack(spacing: 13) {
                Image(systemName: station.hasRealtime ? "tram" : "airplane")
                    .font(.title3)
                    .foregroundStyle(Color.railAccent)
                    .frame(width: 42, height: 46)
                    .background(Color.railAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(station.city).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if favorites.contains(station.id) {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.railAccent)
                        .accessibilityLabel("Pinned")
                }
            }
            .padding(.vertical, 7)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleFavorite(station)
            } label: {
                Label(favorites.contains(station.id) ? "Unpin" : "Pin", systemImage: "pin")
            }
            .tint(.railAccent)
        }
        .contextMenu {
            Button(favorites.contains(station.id) ? "Unpin station" : "Pin station", systemImage: "pin") {
                toggleFavorite(station)
            }
        }
        .accessibilityAction(named: favorites.contains(station.id) ? "Unpin station" : "Pin station") {
            toggleFavorite(station)
        }
    }

    private func toggleFavorite(_ station: Station) {
        var updated = favorites
        if updated.contains(station.id) { updated.remove(station.id) }
        else { updated.insert(station.id) }
        favoriteCodes = updated.sorted().joined(separator: "|")
    }
}

#Preview { StationListView() }
