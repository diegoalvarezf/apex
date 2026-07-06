import SwiftUI

struct PersonalRecordsView: View {
    let activities: [StravaActivity]

    // Represents a single personal record
    private struct PersonalRecord: Identifiable {
        let id = UUID()
        let category: String
        let icon: String
        let iconColor: Color
        let value: String
        let date: Date
        let activity: StravaActivity
    }

    // Compute PRs grouped by sport type
    private var recordsBySport: [(sport: String, emoji: String, records: [PersonalRecord])] {
        let grouped = Dictionary(grouping: activities) { $0.sportType.lowercased() }
        var result: [(sport: String, emoji: String, records: [PersonalRecord])] = []

        for (sportType, acts) in grouped {
            let emoji = acts.first?.sportEmoji ?? "bolt"
            var recs: [PersonalRecord] = []

            // Longest distance
            let distanceActs = acts.filter { $0.distance > 0 }
            if let pr = distanceActs.max(by: { $0.distance < $1.distance }) {
                recs.append(PersonalRecord(
                    category: "Mayor distancia",
                    icon: "arrow.right.circle.fill",
                    iconColor: .blue,
                    value: pr.formattedDistance,
                    date: pr.startDate,
                    activity: pr
                ))
            }

            // Fastest (max speed)
            let speedActs = acts.filter { $0.maxSpeed > 0 }
            if let pr = speedActs.max(by: { $0.maxSpeed < $1.maxSpeed }) {
                recs.append(PersonalRecord(
                    category: "Velocidad maxima",
                    icon: "gauge.with.needle.fill",
                    iconColor: .orange,
                    value: String(format: "%.1f km/h", pr.maxSpeed * 3.6),
                    date: pr.startDate,
                    activity: pr
                ))
            }

            // Greatest elevation
            let elevationActs = acts.filter { $0.totalElevationGain > 0 }
            if let pr = elevationActs.max(by: { $0.totalElevationGain < $1.totalElevationGain }) {
                recs.append(PersonalRecord(
                    category: "Mayor desnivel",
                    icon: "mountain.2.fill",
                    iconColor: .green,
                    value: String(format: "%.0f m", pr.totalElevationGain),
                    date: pr.startDate,
                    activity: pr
                ))
            }

            // Longest duration
            if let pr = acts.max(by: { $0.movingTime < $1.movingTime }) {
                recs.append(PersonalRecord(
                    category: "Mayor duracion",
                    icon: "clock.fill",
                    iconColor: .purple,
                    value: pr.formattedDuration,
                    date: pr.startDate,
                    activity: pr
                ))
            }

            // Highest suffer score (hardest effort)
            let sufferActs = acts.compactMap { act -> (StravaActivity, Int)? in
                guard let ss = act.sufferScore else { return nil }
                return (act, ss)
            }
            if let (pr, ss) = sufferActs.max(by: { $0.1 < $1.1 }) {
                recs.append(PersonalRecord(
                    category: "Esfuerzo maximo",
                    icon: "flame.fill",
                    iconColor: .red,
                    value: "\(ss) pts",
                    date: pr.startDate,
                    activity: pr
                ))
            }

            if !recs.isEmpty {
                result.append((sport: sportType, emoji: emoji, records: recs))
            }
        }

        return result.sorted { $0.sport < $1.sport }
    }

    var body: some View {
        Group {
            if activities.isEmpty {
                ContentUnavailableView(
                    "Sin actividades",
                    systemImage: "trophy",
                    description: Text("Carga actividades desde Strava para ver tus records")
                )
            } else {
                List {
                    ForEach(recordsBySport, id: \.sport) { group in
                        Section {
                            ForEach(group.records) { rec in
                                NavigationLink(destination: ActivityDetailView(activity: rec.activity)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: rec.icon)
                                            .foregroundColor(rec.iconColor)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rec.category)
                                                .font(.subheadline).fontWeight(.semibold)
                                            Text(rec.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption).foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text(rec.value)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundColor(rec.iconColor)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(group.emoji)
                                Text(group.sport.capitalized)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Records personales")
        .navigationBarTitleDisplayMode(.inline)
    }
}
