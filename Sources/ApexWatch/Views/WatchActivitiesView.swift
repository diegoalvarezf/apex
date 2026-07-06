import SwiftUI

struct WatchActivitiesView: View {
    let data: WatchDashboardData

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatDistance(_ meters: Double) -> String? {
        guard meters > 100 else { return nil }
        return meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    var body: some View {
        Group {
            if data.recentActivities.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Sin actividades")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                List(data.recentActivities) { act in
                    HStack(spacing: 8) {
                        Text(act.emoji)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(act.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(formatDuration(act.durationSeconds))
                                if let dist = formatDistance(act.distanceMeters) {
                                    Text("·").foregroundStyle(.secondary)
                                    Text(dist)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.carousel)
            }
        }
        .navigationTitle("Actividades")
    }
}
