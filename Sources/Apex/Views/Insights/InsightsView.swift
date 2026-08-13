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
            await dashVM.loadAlertsIfStale(health: healthKit,
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

    // Contexto de la app en texto para el chat del coach
    private func chatContext() -> String {
        dashVM.coachContext(health: healthKit, strengthSummary: strengthSummary()).contextText()
    }

    // Alertas del día: escritas por la IA (1×/día); reglas locales de fallback
    private var displayedTips: [SmartTip] {
        dashVM.aiAlerts.isEmpty ? smartTips : dashVM.aiAlerts.map(\.asSmartTip)
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

                    // ── Chat con el coach ─────────────────────────────────
                    NavigationLink { CoachChatView(context: chatContext()) } label: {
                        AskCoachCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    // ── Resumen semanal IA ────────────────────────────────
                    if let summary = dashVM.weeklySummary {
                        WeeklySummaryCard(
                            text: summary,
                            date: dashVM.weeklySummaryAt,
                            isLoading: dashVM.isLoadingWeekly,
                            onRefresh: {
                                Task {
                                    await dashVM.reloadWeeklySummary(
                                        health: healthKit, strengthSummary: strengthSummary())
                                }
                            }
                        )
                        .padding(.horizontal)
                    }

                    // ── Alertas del día ───────────────────────────────────
                    if dashVM.isLoadingAlerts && dashVM.aiAlerts.isEmpty {
                        AlertsLoadingBanner().padding(.horizontal)
                    } else if !displayedTips.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Alertas de hoy", systemImage: "sparkles").font(.headline)
                                Spacer()
                                if !dashVM.aiAlerts.isEmpty, let at = dashVM.aiAlertsAt {
                                    Text(Calendar.current.isDateInToday(at)
                                         ? "Hoy " + at.formatted(date: .omitted, time: .shortened)
                                         : at.formatted(.relative(presentation: .named)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 4)

                            SmartTipsList(tips: displayedTips, showAll: showAllTips)

                            if displayedTips.count > 3 {
                                Button {
                                    withAnimation { showAllTips.toggle() }
                                } label: {
                                    Text(showAllTips ? "Ver menos" : "Ver \(displayedTips.count - 3) más")
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
            .navigationTitle("Apex IA")
            .onAppear { analyzeIfStale() }
        }
    }
}

// MARK: - Acceso al chat

private struct AskCoachCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.purple.opacity(0.18), .blue.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pregúntale al coach").font(.headline).foregroundStyle(.primary)
                Text("Dudas sobre tu forma, entrenos o progreso").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.purple.opacity(0.10), Color.blue.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.purple.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Resumen semanal

private struct WeeklySummaryCard: View {
    let text: String
    let date: Date?
    var isLoading: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Resumen de la semana").font(.headline)
                Spacer()
                if let date, !isLoading {
                    Text(date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isLoading {
                HStack(spacing: 10) {
                    Text("Actualizando…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Mismo cuerpo que el resto de análisis: viñetas y conclusión destacada.
            // Los resúmenes ya cacheados, que son prosa, siguen saliendo como párrafo.
            AIAnalysisBody(text: text)
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
