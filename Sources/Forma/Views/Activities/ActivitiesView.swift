import SwiftUI

struct ActivitiesView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @State private var searchText = ""

    var filteredActivities: [StravaActivity] {
        if searchText.isEmpty { return dashVM.activities }
        return dashVM.activities.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.sportType.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if dashVM.isLoadingActivities && dashVM.activities.isEmpty {
                    ProgressView("Cargando actividades...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if dashVM.activities.isEmpty {
                    ContentUnavailableView("Sin actividades", systemImage: "figure.run.circle", description: Text("Conecta con Strava para ver tus actividades"))
                } else {
                    List(filteredActivities) { activity in
                        NavigationLink(destination: ActivityDetailView(activity: activity)) {
                            ActivityRowView(activity: activity)
                        }
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Actividades")
            .searchable(text: $searchText, prompt: "Buscar actividad")
            .refreshable {
                if let token = stravaAuth.accessToken {
                    await dashVM.loadActivities(token: token)
                }
            }
        }
    }
}

struct ActivityRowView: View {
    let activity: StravaActivity

    var body: some View {
        HStack(spacing: 12) {
            Text(activity.sportEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(activity.startDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    if activity.distance > 0 {
                        Label(activity.formattedDistance, systemImage: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Label(activity.formattedDuration, systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let hr = activity.averageHeartrate {
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(String(format: "%.0f", hr))
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
