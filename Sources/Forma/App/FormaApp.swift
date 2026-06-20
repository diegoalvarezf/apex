import SwiftUI

@main
struct FormaApp: App {
    @StateObject private var stravaAuth = StravaAuthManager()
    @StateObject private var healthKit = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(stravaAuth)
                .environmentObject(healthKit)
                .onOpenURL { url in
                    stravaAuth.handleCallback(url: url)
                }
        }
    }
}
