import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var stravaAuth: StravaAuthManager

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Hero: Body Battery
                    BodyBatteryCard(
                        score: healthKit.recoveryScore,
                        summary: healthKit.todaySummary
                    )
                    .padding(.horizontal)

                    // Training load
                    if let load = dashVM.trainingLoad {
                        NavigationLink(destination: TrainingLoadDetailView(load: load, activities: dashVM.activities)) {
                            TrainingLoadCard(load: load)
                                .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }

                    // Quick metrics grid
                    QuickMetricsGrid(
                        summary: healthKit.todaySummary,
                        hrvHistory: healthKit.hrvHistory,
                        vo2MaxData: healthKit.vo2MaxData,
                        respiratoryData: healthKit.respiratoryData,
                        wristTempData: healthKit.wristTempData,
                        daylightData: healthKit.daylightData
                    )
                    .padding(.horizontal)

                    // Recent activities
                    if !dashVM.activities.isEmpty {
                        RecentActivitiesCard(activities: Array(dashVM.activities.prefix(3)))
                            .padding(.horizontal)
                    }

                    if dashVM.isLoadingActivities {
                        ProgressView().padding()
                    }
                }
                .padding(.top)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Apex")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let athlete = stravaAuth.athlete {
                        AsyncImage(url: URL(string: athlete.profile)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color(.tertiarySystemFill))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    }
                }
            }
        }
    }
}

private struct RecentActivitiesCard: View {
    let activities: [StravaActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Últimas actividades")
                    .font(.headline)
                Spacer()
                NavigationLink("Ver todas") {
                    ActivitiesView()
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                NavigationLink(destination: ActivityDetailView(activity: activity)) {
                    ActivityRowView(activity: activity)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                if index < activities.count - 1 {
                    Divider().padding(.leading, 72)
                }
            }
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
