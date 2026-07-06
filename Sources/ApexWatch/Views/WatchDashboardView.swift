import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var store: WatchDataStore

    var body: some View {
        TabView {
            WatchBatteryView(data: store.data)
            WatchMetricsView(data: store.data)
            WatchActivitiesView(data: store.data)
        }
        .tabViewStyle(.page)
    }
}
