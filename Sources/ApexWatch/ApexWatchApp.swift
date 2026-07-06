import SwiftUI

@main
struct ApexWatchApp: App {
    @StateObject private var store = WatchDataStore.shared

    init() {
        WatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(store)
        }
    }
}
