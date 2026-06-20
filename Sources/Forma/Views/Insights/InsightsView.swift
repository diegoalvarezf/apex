import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var stravaAuth: StravaAuthManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if dashVM.isLoadingInsights {
                        AILoadingCard()
                            .padding(.horizontal)
                    } else if dashVM.insights.isEmpty {
                        GenerateInsightsCard {
                            Task { await dashVM.loadInsights(health: healthKit) }
                        }
                        .padding(.horizontal)
                    } else {
                        ForEach(dashVM.insights) { insight in
                            InsightCard(insight: insight)
                                .padding(.horizontal)
                        }

                        Button {
                            Task { await dashVM.loadInsights(health: healthKit) }
                        } label: {
                            Label("Actualizar análisis", systemImage: "arrow.clockwise")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding()
                    }
                }
                .padding(.top)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("IA Coach")
        }
    }
}

private struct GenerateInsightsCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 8) {
                Text("Tu entrenador de IA")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Analiza tus datos de Strava y Apple Health para darte recomendaciones personalizadas.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                Label("Analizar mis datos", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
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

private struct AILoadingCard: View {
    @State private var dots = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.pulse)

            Text("Analizando tus datos" + String(repeating: ".", count: dots + 1))
                .font(.headline)
                .foregroundColor(.secondary)
                .onReceive(timer) { _ in
                    dots = (dots + 1) % 3
                }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct InsightCard: View {
    let insight: AIInsight
    @State private var isExpanded = false

    var categoryColor: Color {
        switch insight.category {
        case .recovery: return .green
        case .training: return .blue
        case .sleep: return .purple
        case .nutrition: return .orange
        case .performance: return .cyan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring()) { isExpanded.toggle() } }) {
                HStack(spacing: 14) {
                    Image(systemName: insight.category.icon)
                        .font(.title3)
                        .foregroundColor(categoryColor)
                        .frame(width: 44, height: 44)
                        .background(categoryColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(insight.category.rawValue.uppercased())
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(categoryColor)
                            Spacer()
                            if insight.priority == .high {
                                Text("Prioritario")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(insight.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(insight.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !insight.recommendations.isEmpty {
                        Text("Recomendaciones")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ForEach(insight.recommendations, id: \.self) { rec in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(categoryColor)
                                    .font(.subheadline)
                                Text(rec)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
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
