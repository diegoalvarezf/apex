import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var stravaAuth: StravaAuthManager

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    RecoveryBatteryCard(score: healthKit.recoveryScore)
                        .padding(.horizontal)

                    if let load = dashVM.trainingLoad {
                        TrainingLoadCard(load: load)
                            .padding(.horizontal)
                    }

                    TodayStatsRow(summary: healthKit.todaySummary)
                        .padding(.horizontal)

                    if !dashVM.activities.isEmpty {
                        RecentActivitiesCard(activities: Array(dashVM.activities.prefix(3)))
                            .padding(.horizontal)
                    }

                    if dashVM.isLoadingActivities {
                        ProgressView()
                            .padding()
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
                            Circle().fill(Color.orange.opacity(0.3))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    }
                }
            }
        }
    }
}

private struct TodayStatsRow: View {
    let summary: DailyHealthSummary?

    var body: some View {
        HStack(spacing: 12) {
            StatMiniCard(
                icon: "flame.fill",
                color: .orange,
                value: summary.map { String(format: "%.0f", $0.activeCalories) } ?? "--",
                unit: "kcal"
            )
            StatMiniCard(
                icon: "figure.walk",
                color: .green,
                value: summary.map { "\($0.steps)" } ?? "--",
                unit: "pasos"
            )
            StatMiniCard(
                icon: "waveform.path.ecg",
                color: .red,
                value: summary?.restingHR.map { String(format: "%.0f", $0) } ?? "--",
                unit: "bpm"
            )
        }
    }
}

struct StatMiniCard: View {
    let icon: String
    let color: Color
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct RecentActivitiesCard: View {
    let activities: [StravaActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Últimas actividades")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                NavigationLink(destination: ActivityDetailView(activity: activity)) {
                    ActivityRowView(activity: activity)
                }
                .buttonStyle(.plain)

                if index < activities.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
