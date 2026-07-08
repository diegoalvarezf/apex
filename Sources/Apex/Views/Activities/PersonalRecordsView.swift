import SwiftUI

struct PersonalRecordsView: View {
    let activities: [StravaActivity]

    // MARK: - Modelo

    private struct PersonalRecord: Identifiable {
        let id = UUID()
        let category: String
        let icon: String
        let value: String
        let unit: String
        let date: Date
        let activity: StravaActivity
    }

    private struct SportGroup: Identifiable {
        var id: String { sport }
        let sport: String
        let label: String
        let icon: String
        let color: Color
        let records: [PersonalRecord]
    }

    // MARK: - Cálculo de récords por deporte

    private var recordsBySport: [SportGroup] {
        let grouped = Dictionary(grouping: activities) { $0.sportType.lowercased() }

        return grouped.compactMap { sportType, acts -> SportGroup? in
            guard let sample = acts.first else { return nil }
            var recs: [PersonalRecord] = []

            if let pr = acts.filter({ $0.distance > 0 }).max(by: { $0.distance < $1.distance }) {
                recs.append(.init(category: "Mayor distancia", icon: "arrow.left.and.right",
                                  value: prValue(pr.formattedDistance).0, unit: prValue(pr.formattedDistance).1,
                                  date: pr.startDate, activity: pr))
            }
            if let pr = acts.filter({ $0.maxSpeed > 0 }).max(by: { $0.maxSpeed < $1.maxSpeed }) {
                recs.append(.init(category: "Velocidad máxima", icon: "gauge.with.needle",
                                  value: String(format: "%.1f", pr.maxSpeed * 3.6), unit: "km/h",
                                  date: pr.startDate, activity: pr))
            }
            if let pr = acts.filter({ $0.totalElevationGain > 0 }).max(by: { $0.totalElevationGain < $1.totalElevationGain }) {
                recs.append(.init(category: "Mayor desnivel", icon: "mountain.2",
                                  value: String(format: "%.0f", pr.totalElevationGain), unit: "m",
                                  date: pr.startDate, activity: pr))
            }
            if let pr = acts.max(by: { $0.movingTime < $1.movingTime }) {
                recs.append(.init(category: "Mayor duración", icon: "clock",
                                  value: pr.formattedDuration, unit: "",
                                  date: pr.startDate, activity: pr))
            }
            if let (pr, ss) = acts.compactMap({ act in act.sufferScore.map { (act, $0) } }).max(by: { $0.1 < $1.1 }) {
                recs.append(.init(category: "Esfuerzo máximo", icon: "flame",
                                  value: "\(ss)", unit: "pts",
                                  date: pr.startDate, activity: pr))
            }

            guard !recs.isEmpty else { return nil }
            return SportGroup(sport: sportType, label: sample.sportLabel,
                              icon: sample.sportIcon, color: sample.sportColor, records: recs)
        }
        .sorted { $0.records.count > $1.records.count }
    }

    // Separa "12.34 km" en (valor, unidad) para poder darles jerarquía tipográfica
    private func prValue(_ s: String) -> (String, String) {
        let parts = s.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return (s, "") }
        return (String(parts[0]), String(parts[1]))
    }

    // MARK: - Vista

    var body: some View {
        Group {
            if recordsBySport.isEmpty {
                ContentUnavailableView(
                    "Sin récords todavía",
                    systemImage: "trophy",
                    description: Text("Registra actividades en Strava para desbloquear tus mejores marcas.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(recordsBySport) { group in
                            SportRecordsCard(group: group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Récords personales")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Card por deporte

    private struct SportRecordsCard: View {
        let group: SportGroup

        var body: some View {
            VStack(spacing: 0) {
                // Cabecera del deporte
                HStack(spacing: 12) {
                    IconBadge(icon: group.icon, color: group.color, size: 34, corner: 9)
                    Text(group.label)
                        .font(.headline)
                    Spacer()
                    Text("\(group.records.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ForEach(Array(group.records.enumerated()), id: \.element.id) { idx, rec in
                    NavigationLink(destination: ActivityDetailView(activity: rec.activity)) {
                        RecordRow(rec: rec)
                    }
                    .buttonStyle(.plain)

                    if idx < group.records.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
                .padding(.bottom, 6)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Fila de récord

    private struct RecordRow: View {
        let rec: PersonalRecord

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: rec.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)

                Text(rec.category)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(rec.value)
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if !rec.unit.isEmpty {
                        Text(rec.unit)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Badge de icono estilo Ajustes de iOS (solo cabecera de deporte)

    private struct IconBadge: View {
        let icon: String
        let color: Color
        var size: CGFloat = 30
        var corner: CGFloat = 8

        var body: some View {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.gradient)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}
