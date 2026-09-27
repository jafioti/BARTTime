import SwiftUI

extension Color {
    static let railAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.80, blue: 0.93, alpha: 1)
            : UIColor(red: 0.03, green: 0.38, blue: 0.50, alpha: 1)
    })
    static let railBackground = Color(uiColor: .systemGroupedBackground)
    static let railCard = Color(uiColor: .secondarySystemGroupedBackground)
}

extension RailLine {
    var color: Color {
        switch code {
        case "YELLOW": return Color(red: 0.96, green: 0.75, blue: 0.16)
        case "BLUE": return Color(red: 0.14, green: 0.58, blue: 0.83)
        case "GREEN": return Color(red: 0.26, green: 0.66, blue: 0.42)
        case "RED": return Color(red: 0.88, green: 0.30, blue: 0.35)
        case "ORANGE": return Color(red: 0.94, green: 0.53, blue: 0.19)
        case "BEIGE": return Color(red: 0.71, green: 0.62, blue: 0.46)
        default: return .secondary
        }
    }
}

struct RailStripes: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["YELLOW", "BLUE", "GREEN", "RED", "ORANGE"], id: \.self) { code in
                Capsule().fill(RailLine(code).color).frame(width: 24, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct NoticeView: View {
    let text: String
    var symbol = "wifi.exclamationmark"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct BARTAttribution: View {
    var body: some View {
        VStack(spacing: 6) {
            Link("Data provided by BART ↗", destination: URL(string: "https://www.bart.gov")!)
                .font(.caption.weight(.medium))
            Text("An independent app for your everyday ride.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
