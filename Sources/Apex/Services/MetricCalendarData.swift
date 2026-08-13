import Foundation

// Valores diarios que alimentan el calendario mensual.
//
// Salen de las fotos que la app guarda cada día (`DailySnapshotStore`), no de
// recalcular el pasado: los parámetros con los que se calcula (FC en reposo, FCmáx)
// cambian con el tiempo, así que rehacer un día de hace un mes daría un número
// distinto al que se vio entonces. El calendario y el detalle del día beben de la
// misma fuente para que no puedan contradecirse.
//
// Como consecuencia, solo hay histórico desde que la app empezó a guardarlo. Es
// preferible un calendario que se va llenando a uno lleno de reconstrucciones.
enum MetricCalendarData {

    @MainActor
    static func values(
        for metric: MetricCalendarView.Metric,
        healthKit: HealthKitManager,
        activities: [StravaActivity]
    ) -> [Date: Int] {
        let fotos = DailySnapshotStore.shared.all()
        var out: [Date: Int] = [:]

        for (dia, snap) in fotos {
            switch metric {
            case .battery:  if let v = snap.battery  { out[dia] = v }
            case .recovery: if let v = snap.recovery { out[dia] = v }
            case .stress:   if let v = snap.stress   { out[dia] = v }
            }
        }

        // Body Battery tiene además los cierres que el propio store lleva guardando
        // desde antes de existir las fotos. Son valores reales de aquel día, así que
        // se usan para los días que la foto no cubre.
        if metric == .battery {
            for (dia, valor) in BodyBatteryStore.shared.storedDailyValues() where out[dia] == nil {
                out[dia] = Int(valor.rounded())
            }
        }
        return out
    }

    static func disponibilidad(_ metric: MetricCalendarView.Metric) -> String {
        switch metric {
        case .battery:
            return "Valores guardados cada día. Se conservan 90 días."
        case .recovery, .stress:
            return "Solo aparecen los días que la app registró: el histórico se va llenando a partir de ahora, no se reconstruye."
        }
    }
}
