import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var routineVM: RoutineViewModel

    @State private var showAllTips = false

    private func analyze() {
        Task { await dashVM.loadInsights(health: healthKit,
                                         strengthSummary: strengthSummary(),
                                         localAlerts: localAlerts()) }
    }

    // Auto-análisis: solo si no hay uno de hoy (1×/día). El resto se sirve de caché.
    private func analyzeIfStale() {
        Task {
            await dashVM.loadInsightsIfStale(health: healthKit,
                                             strengthSummary: strengthSummary(),
                                             localAlerts: localAlerts())
            await dashVM.loadWeeklySummaryIfStale(health: healthKit,
                                                  strengthSummary: strengthSummary())
        }
    }

    // Las alertas locales que ya ve el usuario, para que la IA no las repita
    private func localAlerts() -> String? {
        let tips = smartTips
        guard !tips.isEmpty else { return nil }
        return tips.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
    }

    // Progresión de peso por ejercicio (de las rutinas), para que la IA analice el gimnasio
    private func strengthSummary() -> String? {
        var lines: [String] = []
        for r in routineVM.routines {
            for d in r.days {
                for ex in d.exercises {
                    let entries = RoutineProgressStore.shared.entries(for: ex.id)
                    guard !entries.isEmpty else { continue }
                    let series = entries.suffix(5)
                        .map { $0.weight == $0.weight.rounded() ? "\(Int($0.weight))" : String(format: "%.1f", $0.weight) }
                        .joined(separator: "→")
                    lines.append("  \(ex.name): \(series) kg")
                }
            }
        }
        guard !lines.isEmpty else { return nil }
        return Array(Set(lines)).sorted().prefix(20).joined(separator: "\n")
    }

    private var smartTips: [SmartTip] {
        SmartTipsEngine.compute(
            recovery: healthKit.recoveryScore,
            sleep: healthKit.sleepHistory.first,
            sleepHistory: healthKit.sleepHistory,
            hourlyHR: healthKit.recentHourlyHR,
            rhr: healthKit.todaySummary?.restingHR,
            rhrHistory: healthKit.restingHRHistory,
            hrvHistory: healthKit.hrvHistory,
            activities: dashVM.activities
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Resumen semanal IA ────────────────────────────────
                    if let summary = dashVM.weeklySummary {
                        WeeklySummaryCard(text: summary, date: dashVM.weeklySummaryAt)
                            .padding(.horizontal)
                    }

                    // ── Sugerencias locales (instantáneas) ────────────────
                    if !smartTips.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Alertas de hoy", systemImage: "sparkles")
                                .font(.headline)
                                .padding(.horizontal, 4)

                            SmartTipsList(tips: smartTips, showAll: showAllTips)

                            if smartTips.count > 3 {
                                Button {
                                    withAnimation { showAllTips.toggle() }
                                } label: {
                                    Text(showAllTips ? "Ver menos" : "Ver \(smartTips.count - 3) más")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // ── Separador ─────────────────────────────────────────
                    HStack {
                        Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                        Text("Análisis IA").font(.caption).foregroundColor(.secondary).fixedSize()
                        Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                    }
                    .padding(.horizontal)

                    // ── Insights Claude ────────────────────────────────────
                    if dashVM.isLoadingInsights {
                        AILoadingCard()
                            .padding(.horizontal)
                    } else if dashVM.insights.isEmpty {
                        GenerateInsightsCard {
                            analyze()
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(dashVM.insights) { insight in
                                InsightCard(insight: insight)
                            }
                        }
                        .padding(.horizontal)

                        VStack(spacing: 6) {
                            if let at = dashVM.insightsGeneratedAt {
                                Text("Actualizado \(at.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Button {
                                analyze()
                            } label: {
                                Label("Actualizar análisis", systemImage: "arrow.clockwise")
                                    .font(.subheadline).fontWeight(.medium)
                            }
                        }
                        .padding()
                    }
                }
                .padding(.top)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("IA Coach")
            .onAppear { analyzeIfStale() }
        }
    }
}

// MARK: - Resumen semanal

private struct WeeklySummaryCard: View {
    let text: String
    let date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Resumen de la semana").font(.headline)
                Spacer()
                if let date {
                    Text(date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.purple.opacity(0.10), Color.blue.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.purple.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Generate / Empty state

private struct GenerateInsightsCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.08)).frame(width: 80, height: 80)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(spacing: 6) {
                Text("Análisis personalizado").font(.title3).fontWeight(.bold)
                Text("Claude analiza tus datos de Strava y Apple Health y te da recomendaciones concretas sobre recuperación, sueño y planificación del entrenamiento.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                Label("Analizar ahora", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [.purple, .blue],
                                              startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Loading

private struct AILoadingCard: View {
    @State private var dots = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [.purple, .blue],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.pulse)

            Text("Analizando tus datos" + String(repeating: ".", count: dots + 1))
                .font(.headline).foregroundColor(.secondary)
                .onReceive(timer) { _ in dots = (dots + 1) % 3 }
        }
        .frame(maxWidth: .infinity).padding(40)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Insight card (Claude)

struct InsightCard: View {
    let insight: AIInsight
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring()) { isExpanded.toggle() } }) {
                HStack(spacing: 14) {
                    Image(systemName: insight.category.icon)
                        .font(.title3)
                        .foregroundColor(insight.category.color)
                        .frame(width: 44, height: 44)
                        .background(insight.category.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(insight.category.displayName.uppercased())
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundColor(insight.category.color)
                            Spacer()
                            if insight.priority == .high {
                                Text("Prioritario").font(.caption2).fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.red).clipShape(Capsule())
                            }
                        }
                        Text(insight.title)
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 12) {
                    Text(insight.body).font(.subheadline).foregroundColor(.secondary)
                    if !insight.recommendations.isEmpty {
                        Text("Recomendaciones").font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary).textCase(.uppercase)
                        ForEach(insight.recommendations, id: \.self) { rec in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(insight.category.color).font(.subheadline)
                                Text(rec).font(.subheadline).foregroundColor(.primary)
                            }
                        }
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
