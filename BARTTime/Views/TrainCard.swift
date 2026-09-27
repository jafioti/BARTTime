import SwiftUI

struct TrainCard: View {
    let departure: Departure
    let isStale: Bool
    let origin: String
    let pins: [Station]
    let timetables: [RouteTimetable]
    let sourceDate: Date
    let arrivalsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(departure.line.color)
                    .frame(width: 10, height: 10).padding(.top, 5)
                    .accessibilityLabel(departure.line.name)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Toward \(departure.destination)")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(details).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(departure.time.label)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    if case .minutes = departure.time {
                        Text("min").font(.caption).foregroundStyle(.secondary)
                    }
                    if isStale {
                        Text("Last estimate").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isStale ? "Last known: " : "")\(departure.time.accessibilityLabel)")
            }
            if arrivalsAvailable {
                let arrivals = ArrivalEstimator.arrivals(for: departure, origin: origin, pins: pins,
                                                         timetables: timetables, sourceDate: sourceDate)
                ForEach(arrivals) { arrival in
                    HStack(alignment: .firstTextBaseline) {
                        Label(arrival.station.name, systemImage: "pin.fill")
                        Spacer(minLength: 8)
                        Text("≈\(arrival.minutes) min · \(arrival.date.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if departure.delaySeconds >= 60 {
                Label("Running about \(Int((Double(departure.delaySeconds) / 60).rounded())) min behind schedule", systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.railCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
        }
    }

    private var details: String {
        var parts: [String] = []
        if !departure.direction.isEmpty { parts.append("\(departure.direction)bound") }
        if !departure.platform.isEmpty { parts.append("Platform \(departure.platform)") }
        if let cars = departure.cars, cars > 0 { parts.append("\(cars)-car train") }
        return parts.joined(separator: " · ")
    }
}
