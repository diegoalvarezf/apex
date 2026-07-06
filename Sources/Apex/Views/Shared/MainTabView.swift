import SwiftUI

struct MainTabView: View {
    @StateObject private var dashVM = DashboardViewModel()
    @StateObject private var routineVM = RoutineViewModel()
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Inicio", systemImage: "house.fill") }

            HealthView()
                .tabItem { Label("Salud", systemImage: "heart.fill") }

            ActivitiesView()
                .tabItem { Label("Actividades", systemImage: "figure.run") }

            RoutineView()
                .tabItem { Label("Rutina", systemImage: "calendar") }

            InsightsView()
                .tabItem { Label("IA Coach", systemImage: "sparkles") }
        }
        .tint(.primary)
        .environmentObject(dashVM)
        .environmentObject(routineVM)
        .task {
            // Renovar token antes de cualquier llamada a la API
            await stravaAuth.refreshTokenIfNeeded()
            if let token = stravaAuth.accessToken {
                await dashVM.loadActivities(token: token)
            }
            if !healthKit.isAuthorized {
                await healthKit.requestAuthorization()
            }
        }
    }
}
