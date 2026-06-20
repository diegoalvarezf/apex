import SwiftUI
import MapKit

struct ActivityDetailView: View {
    let activity: StravaActivity
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ActivityHeaderCard(activity: activity)
                    .padding(.horizontal)

                StatsGrid(activity: activity)
                    .padding(.horizontal)

                if let hr = activity.averageHeartrate {
                    HeartRateCard(avg: hr, max: activity.maxHeartrate)
                        .padding(.horizontal)
                }

                if let watts = activity.averageWatts {
                    PowerCard(avg: watts, weighted: activity.weightedAverageWatts, kj: activity.kilojoules)
                        .padding(.horizontal)
                }

                if let sufferScore = activity.sufferScore {
                    SufferScoreCard(score: sufferScore)
                        .padding(.horizontal)
                }
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityHeaderCard: View {
    let activity: StravaActivity

    var body: some View {
        HStack(spacing: 16) {
            Text(activity.sportEmoji)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.sportType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(activity.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(activity.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatsGrid: View {
    let activity: StravaActivity

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if activity.distance > 0 {
                StatCell(title: "Distancia", value: activity.formattedDistance, icon: "arrow.right.circle.fill", color: .blue)
            }
            StatCell(title: "Tiempo", value: activity.formattedDuration, icon: "clock.fill", color: .purple)
            if activity.distance > 0 {
                StatCell(title: "Ritmo", value: activity.formattedPace, icon: "gauge.with.needle.fill", color: .orange)
            }
            if activity.totalElevationGain > 0 {
                StatCell(title: "Desnivel", value: String(format: "%.0f m", activity.totalElevationGain), icon: "mountain.2.fill", color: .green)
            }
        }
    }
}

struct StatCell: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct HeartRateCard: View {
    let avg: Double
    let max: Double?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                Text(String(format: "%.0f", avg))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                Text("FC media")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            if let max {
                Divider().frame(height: 60)
                VStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red.opacity(0.5))
                    Text(String(format: "%.0f", max))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("FC máxima")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct PowerCard: View {
    let avg: Double
    let weighted: Int?
    let kj: Double?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text(String(format: "%.0f W", avg))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                Text("Potencia media")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            if let w = weighted {
                Divider().frame(height: 60)
                VStack(spacing: 4) {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.yellow.opacity(0.7))
                    Text("\(w) W")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                    Text("NP")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if let kj {
                Divider().frame(height: 60)
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text(String(format: "%.0f kJ", kj))
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                    Text("Trabajo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SufferScoreCard: View {
    let score: Int

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suffer Score")
                    .font(.headline)
                Text("Esfuerzo relativo de esta actividad")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(sufferColor)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sufferColor: Color {
        switch score {
        case 0..<50: return .blue
        case 50..<100: return .green
        case 100..<150: return .yellow
        case 150..<200: return .orange
        default: return .red
        }
    }
}
