import SwiftUI

struct MainTabView: View {
    @StateObject private var dashVM = DashboardViewModel()
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Inicio", systemImage: "house.fill")
                }

            ActivitiesView()
                .tabItem {
                    Label("Actividades", systemImage: "figure.run")
                }

            HealthView()
                .tabItem {
                    Label("Salud", systemImage: "heart.fill")
                }

            InsightsView()
                .tabItem {
                    Label("IA Coach", systemImage: "sparkles")
                }
        }
        .tint(.primary)
        .environmentObject(dashVM)
        .task {
            if let token = stravaAuth.accessToken {
                await dashVM.loadActivities(token: token)
            }
            if !healthKit.isAuthorized {
                await healthKit.requestAuthorization()
            }
        }
    }
}
