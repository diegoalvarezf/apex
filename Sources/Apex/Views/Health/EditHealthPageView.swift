import SwiftUI

// Editor de la pestaña Salud: reordena las secciones (arrastrando) y muestra/oculta
// cada métrica con el ojo.
struct EditHealthPageView: View {
    @ObservedObject var layout: HealthLayoutStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Arrastra las secciones para reordenarlas y toca el ojo para mostrar u ocultar cada métrica.")
                        .font(.caption).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                ForEach(layout.sectionOrder) { section in
                    Section {
                        let metrics = HealthMetricID.allCases.filter { $0.section == section }
                        if metrics.isEmpty {
                            Text("Sin métricas configurables")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(metrics) { m in
                                Button { layout.toggle(m) } label: {
                                    HStack {
                                        Text(m.title)
                                            .foregroundStyle(layout.isVisible(m) ? .primary : .secondary)
                                        Spacer()
                                        Image(systemName: layout.isVisible(m) ? "eye" : "eye.slash")
                                            .foregroundStyle(layout.isVisible(m) ? Color.accentColor : .secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Label(section.title, systemImage: section.icon)
                    }
                }
                .onMove { layout.moveSections(from: $0, to: $1) }

                Section {
                    Button(role: .destructive) { layout.resetToDefaults() } label: {
                        Label("Restablecer por defecto", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Editar página")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
