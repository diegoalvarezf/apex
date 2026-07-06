import SwiftUI

struct StartActivitySheet: View {
    let onStart: (WorkoutSportType) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selected: WorkoutSportType = .run

    private let outdoor: [WorkoutSportType] = [.run, .ride, .walk, .hike, .trailRun]
    private let indoor: [WorkoutSportType]  = [.weightTraining, .yoga, .swim]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SportSection(title: "Exterior", sports: outdoor, selected: $selected, columns: columns)
                    SportSection(title: "Interior", sports: indoor,  selected: $selected, columns: columns)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nueva actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let sport = selected
                        dismiss()
                        // Pequeño delay para que el sheet cierre antes de fullScreenCover
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onStart(sport)
                        }
                    } label: {
                        Text("Empezar").fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

private struct SportSection: View {
    let title: String
    let sports: [WorkoutSportType]
    @Binding var selected: WorkoutSportType
    let columns: [GridItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sports) { sport in
                    SportCell(sport: sport, isSelected: selected == sport) {
                        withAnimation(.spring(response: 0.25)) { selected = sport }
                    }
                }
            }
        }
    }
}

private struct SportCell: View {
    let sport: WorkoutSportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(sport.emoji).font(.system(size: 34))
                Text(sport.label)
                    .font(.caption).fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
