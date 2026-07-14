import SwiftUI

// MARK: - Categorías de filtro

private struct SportFilter: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    let sportTypes: [String]  // valores de sportType que agrupa

    static let all = SportFilter(id: "all", label: "Todo", icon: "square.grid.2x2", sportTypes: [])

    static let catalog: [SportFilter] = [
        .all,
        SportFilter(id: "run",    label: "Carrera",    icon: "figure.run",
                    sportTypes: ["run", "virtualrun", "trail_run"]),
        SportFilter(id: "ride",   label: "Ciclismo",   icon: "figure.outdoor.cycle",
                    sportTypes: ["ride", "virtualride", "ebikeride", "mountainbikeride", "gravelride"]),
        SportFilter(id: "swim",   label: "Natación",   icon: "figure.pool.swim",
                    sportTypes: ["swim"]),
        SportFilter(id: "hike",   label: "Senderismo", icon: "figure.hiking",
                    sportTypes: ["hike"]),
        SportFilter(id: "walk",   label: "Caminata",   icon: "figure.walk",
                    sportTypes: ["walk"]),
        SportFilter(id: "weight", label: "Pesas",      icon: "dumbbell",
                    sportTypes: ["weighttraining", "crossfit", "workout", "elliptical"]),
        SportFilter(id: "yoga",   label: "Yoga",       icon: "figure.yoga",
                    sportTypes: ["yoga", "pilates"]),
    ]
}

// MARK: - Vista principal

struct ActivitiesView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var workoutStore: WorkoutLogStore

    @State private var searchText = ""
    @State private var selectedFilter: SportFilter = .all
    @State private var showStartSheet = false
    @State private var showLiveActivity = false
    @State private var activeSport: WorkoutSportType = .run
    @State private var showWeeklyStats = true

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    // Solo mostrar filtros con actividades
    private var availableFilters: [SportFilter] {
        let types = Set(dashVM.activities.map { $0.sportType.lowercased() })
        return SportFilter.catalog.filter { f in
            f == .all || f.sportTypes.contains(where: { types.contains($0) })
        }
    }

    private var filteredActivities: [StravaActivity] {
        var list = dashVM.activities

        // Filtro de deporte
        if selectedFilter != .all {
            list = list.filter { selectedFilter.sportTypes.contains($0.sportType.lowercased()) }
        }

        // Búsqueda
        if !searchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.sportType.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    // MARK: - Week helpers

    private var weekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date()) ??
            DateInterval(start: Date(), duration: 604800)
    }

    private var lastWeekInterval: DateInterval {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start) ?? weekInterval.start
        return DateInterval(start: start, end: weekInterval.start)
    }

    private var thisWeekActivities: [StravaActivity] {
        dashVM.activities.filter { weekInterval.contains($0.startDate) }
    }

    private var lastWeekActivities: [StravaActivity] {
        dashVM.activities.filter { lastWeekInterval.contains($0.startDate) }
    }

    private func weekStats(_ acts: [StravaActivity]) -> (km: Double, hours: Double, elevation: Double) {
        let km = acts.reduce(0.0) { $0 + $1.distance } / 1000
        let hours = acts.reduce(0.0) { $0 + Double($1.movingTime) } / 3600
        let elevation = acts.reduce(0.0) { $0 + $1.totalElevationGain }
        return (km, hours, elevation)
    }

    private func pct(_ current: Double, _ previous: Double) -> String? {
        guard previous > 0 else { return nil }
        let diff = (current - previous) / previous * 100
        if diff > 1 { return "+\(Int(diff))%" }
        if diff < -1 { return "\(Int(diff))%" }
        return "igual"
    }

    private func pctColor(_ current: Double, _ previous: Double) -> Color {
        guard previous > 0 else { return .secondary }
        return current >= previous * 0.99 ? .green : .red
    }

    var body: some View {
        NavigationStack {
            Group {
                if dashVM.isLoadingActivities && dashVM.activities.isEmpty {
                    ProgressView("Cargando actividades...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if dashVM.activities.isEmpty {
                    ContentUnavailableView(
                        "Sin actividades",
                        systemImage: "figure.run.circle",
                        description: Text("Conecta con Strava para ver tus actividades")
                    )
                } else {
                    ScrollView {
                        // Sección estadísticas semanales (colapsable)
                        let thisWeek = weekStats(thisWeekActivities)
                        let lastWeek = weekStats(lastWeekActivities)

                        VStack(spacing: 0) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { showWeeklyStats.toggle() }
                            } label: {
                                HStack {
                                    Text("Esta semana")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: showWeeklyStats ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, showWeeklyStats ? 12 : 16)
                            }
                            .buttonStyle(.plain)

                            if showWeeklyStats {
                                HStack(spacing: 0) {
                                    WeekStatCell(
                                        label: "Distancia",
                                        value: String(format: "%.1f km", thisWeek.km),
                                        comparison: pct(thisWeek.km, lastWeek.km),
                                        compColor: pctColor(thisWeek.km, lastWeek.km)
                                    )
                                    Divider().frame(height: 44)
                                    WeekStatCell(
                                        label: "Tiempo",
                                        value: String(format: "%.1f h", thisWeek.hours),
                                        comparison: pct(thisWeek.hours, lastWeek.hours),
                                        compColor: pctColor(thisWeek.hours, lastWeek.hours)
                                    )
                                    Divider().frame(height: 44)
                                    WeekStatCell(
                                        label: "Desnivel",
                                        value: String(format: "%.0f m", thisWeek.elevation),
                                        comparison: pct(thisWeek.elevation, lastWeek.elevation),
                                        compColor: pctColor(thisWeek.elevation, lastWeek.elevation)
                                    )
                                }
                                .padding(.bottom, 16)
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Accesos: récords, estadísticas e historial de pesas
                        HStack(spacing: 10) {
                            NavigationLink(destination: PersonalRecordsView(activities: dashVM.activities)) {
                                ActivityNavCard(icon: "trophy.fill", label: "Récords", color: .yellow)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: ActivityStatsView(activities: dashVM.activities)) {
                                ActivityNavCard(icon: "chart.bar.fill", label: "Estadísticas", color: .blue)
                            }
                            .buttonStyle(.plain)

                            if !workoutStore.logs.isEmpty {
                                NavigationLink(destination: WorkoutHistoryView()) {
                                    ActivityNavCard(icon: "dumbbell.fill", label: "Pesas", color: .purple)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        // Filtros
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableFilters) { filter in
                                    FilterChip(filter: filter, isSelected: selectedFilter == filter) {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedFilter = filter
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }

                        if filteredActivities.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: selectedFilter.icon)
                                    .font(.system(size: 40)).foregroundStyle(.secondary)
                                Text("Sin actividades de \(selectedFilter.label.lowercased())")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(filteredActivities) { activity in
                                    NavigationLink(destination: ActivityDetailView(activity: activity)) {
                                        ActivityCardView(activity: activity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 32)
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Actividades")
            .searchable(text: $searchText, prompt: "Buscar actividad")
            .refreshable {
                if let token = stravaAuth.accessToken {
                    await dashVM.loadActivities(token: token)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showStartSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill").font(.caption)
                            Text("Empezar")
                        }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.primary, in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                }

            }
            .sheet(isPresented: $showStartSheet) {
                StartActivitySheet { sport in
                    activeSport = sport
                    showLiveActivity = true
                }
            }
            .fullScreenCover(isPresented: $showLiveActivity) {
                LiveActivityView(sport: activeSport)
            }
        }
    }
}

// MARK: - Tarjeta de acceso (récords, estadísticas, pesas)

private struct ActivityNavCard: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Weekly stat cell

private struct WeekStatCell: View {
    let label: String
    let value: String
    let comparison: String?
    let compColor: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
            if let comp = comparison {
                Text(comp)
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(compColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Chip de filtro

private struct FilterChip: View {
    let filter: SportFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: filter.icon).font(.system(size: 12, weight: .medium))
                Text(filter.label).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                isSelected ? Color.primary : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card de actividad

struct ActivityCardView: View {
    let activity: StravaActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Cabecera: emoji + fecha
            HStack(alignment: .top) {
                Text(activity.sportEmoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 9))
                Spacer()
                Text(activity.startDate.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            // Nombre
            Text(activity.name)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Stats en 2×2
            VStack(spacing: 4) {
                HStack {
                    MiniStat(value: activity.formattedDuration, icon: "clock")
                    Spacer()
                    if activity.distance > 0 {
                        MiniStat(value: activity.formattedDistance, icon: "arrow.right")
                    }
                }
                HStack {
                    if activity.totalElevationGain > 0 {
                        MiniStat(value: "\(Int(activity.totalElevationGain)) m", icon: "mountain.2")
                    }
                    Spacer()
                    if let hr = activity.averageHeartrate {
                        MiniStat(value: "\(Int(hr)) bpm", icon: "heart")
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MiniStat: View {
    let value: String
    let icon: String

    var body: some View {
        Label(value, systemImage: icon)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

// MARK: - ActivityRowView (usado en dashboard)

struct ActivityRowView: View {
    let activity: StravaActivity

    var body: some View {
        HStack(spacing: 12) {
            Text(activity.sportEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                Text(activity.startDate.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    if activity.distance > 0 {
                        Label(activity.formattedDistance, systemImage: "arrow.right")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Label(activity.formattedDuration, systemImage: "clock")
                        .font(.caption2).foregroundColor(.secondary)
                    if activity.totalElevationGain > 0 {
                        Label("\(Int(activity.totalElevationGain)) m", systemImage: "mountain.2")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if let hr = activity.averageHeartrate {
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill").font(.caption).foregroundColor(.red)
                    Text(String(format: "%.0f", hr)).font(.caption2).fontWeight(.semibold)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
