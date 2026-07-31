import SwiftUI

// Compact inline banner for contextual health tips
// Usage: SmartTipBanner(tips: computedTips)
struct SmartTipBanner: View {
    let tips: [SmartTip]
    var updatedAt: Date? = nil        // cuándo generó la IA estas alertas
    var isAI: Bool = false            // true si vienen de la IA (no reglas locales)
    @State private var current = 0
    @State private var dismissed = false
    @State private var expanded = false

    // "Actualizado hoy 9:31" / "Actualizado ayer" — para saber si están al día
    private var freshnessText: String? {
        guard isAI, let at = updatedAt else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(at) {
            return "Actualizado hoy " + at.formatted(date: .omitted, time: .shortened)
        }
        return "Actualizado " + at.formatted(.relative(presentation: .named))
    }

    var body: some View {
        if dismissed || tips.isEmpty { EmptyView() }
        else {
            VStack(spacing: 6) {
                // Sello de actualización arriba (no descentra los puntos de abajo)
                if let freshnessText {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 9))
                        Text(freshnessText).font(.system(size: 10))
                        Spacer()
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                }

                // Paginación nativa: desliza fino y no interfiere con el resto de la app
                TabView(selection: $current) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { idx, tip in
                        tipCard(tip)
                            .padding(.horizontal, 1)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: expanded ? expandedHeight : 84)
                .animation(.spring(response: 0.3), value: expanded)

                // Puntos indicadores, centrados
                if tips.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(tips.indices, id: \.self) { i in
                            Circle()
                                .fill(i == current ? Color.primary.opacity(0.6) : Color.primary.opacity(0.2))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
    }

    // Altura cuando está desplegada (para que quepa el texto largo)
    private var expandedHeight: CGFloat { 150 }

    @ViewBuilder
    private func tipCard(_ tip: SmartTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tip.color)
                .frame(width: 34, height: 34)
                .background(tip.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                    .lineLimit(expanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: expanded)
                Text(tip.detail)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: expanded)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button { withAnimation { dismissed = true } } label: {
                    Image(systemName: "xmark").font(.caption2).foregroundStyle(.tertiary)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(tip.color)
                .frame(width: 3).padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3)) { expanded.toggle() } }
    }
}

// Full expandable list — used in InsightsView
struct SmartTipsList: View {
    let tips: [SmartTip]
    var showAll = false

    var body: some View {
        let visible: [SmartTip] = showAll ? tips : Array(tips.prefix(3))
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { idx, tip in
                SmartTipRow(tip: tip)
                if idx < visible.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SmartTipRow: View {
    let tip: SmartTip
    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.spring(response: 0.3)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: tip.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(tip.color)
                        .frame(width: 36, height: 36)
                        .background(tip.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                    Text(tip.title)
                        .font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(14)

                if expanded {
                    Text(tip.detail)
                        .font(.subheadline).foregroundColor(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Banner con spinner mientras la IA genera las alertas del día
struct AlertsLoadingBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Preparando tus alertas de hoy")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                Text("Claude está leyendo tus datos…")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
