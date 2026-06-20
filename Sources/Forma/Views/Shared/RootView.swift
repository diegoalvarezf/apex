import SwiftUI

struct RootView: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        Group {
            if stravaAuth.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: stravaAuth.isAuthenticated)
    }
}
