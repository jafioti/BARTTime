import SwiftUI

@main
@MainActor
struct BARTTimeApp: App {
    var body: some Scene {
        WindowGroup {
            StationListView()
                .tint(.railAccent)
        }
    }
}
