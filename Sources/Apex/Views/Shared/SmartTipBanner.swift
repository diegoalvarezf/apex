import SwiftUI

// Compact inline banner for contextual health tips
// Usage: SmartTipBanner(tips: computedTips)
struct SmartTipBanner: View {
    let tips: [SmartTip]
    @State private var current = 0
    @State private var dismissed = false

    var body: some View {
        if dismissed || tips.isEmpty { EmptyView() }
        else {
            let tip = tips[current]
            HStack(spacing: 12) {
                Image(systemName: tip.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tip.color)
                    .frame(width: 34, height: 34)
                    .background(tip.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title)
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                        .lineLimit(1)
                    Text(tip.detail)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    // Dismiss
                    Button { withAnimation { dismissed = true } } label: {
                        Image(systemName: "xmark").font(.caption2).foregroundStyle(.tertiary)
                    }
                    // Paginator
                    if tips.count > 1 {
                        Text("\(current + 1)/\(tips.count)").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(tip.color)
                    .frame(width: 3).padding(.vertical, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard tips.count > 1 else { return }
                withAnimation { current = (current + 1) % tips.count }
            }
            .transition(.asymmetric(insertion: .push(from: .top), removal: .push(from: .bottom)))
            .animation(.spring(response: 0.4), value: current)
        }
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
