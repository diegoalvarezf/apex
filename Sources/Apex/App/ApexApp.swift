import SwiftUI

@main
struct ApexApp: App {
    @StateObject private var stravaAuth = StravaAuthManager()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var profileManager = UserProfileManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var workoutStore = WorkoutLogStore.shared
    private let phoneConnectivity = PhoneConnectivityManager.shared

    init() { BackgroundRefresh.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(stravaAuth)
                .environmentObject(healthKit)
                .environmentObject(profileManager)
                .environmentObject(notificationManager)
                .environmentObject(workoutStore)
                .onOpenURL { url in
                    stravaAuth.handleCallback(url: url)
                }
                .task { BackgroundRefresh.schedule() }
        }
    }
}
