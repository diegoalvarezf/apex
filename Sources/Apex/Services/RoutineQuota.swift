import Foundation

// Cuántas rutinas puede generar el usuario al mes.
//
// Generar una rutina es, con diferencia, la llamada más cara de la app: usa el
// modelo grande y hasta 8.000 tokens, cuando el resto de análisis usan el modelo
// pequeño y unos cientos. Un solo usuario generando rutinas a diario costaría más
// que decenas de usuarios normales, así que el tope existe para que el coste por
// usuario sea acotado y previsible.
//
// Cuatro al mes es holgado para el uso real —una rutina se cambia cada varias
// semanas— y para retocar un ejercicio suelto está `ExerciseSwapper`, que no
// consume cuota porque cuesta una fracción.
enum RoutineQuota {

    static let porMes = 4

    private static let storageKey = "apex_routine_generations"
    private static let cal = Calendar.current

    // Generaciones del mes en curso.
    static func usadas(hoy: Date = Date()) -> Int {
        fechas().filter { cal.isDate($0, equalTo: hoy, toGranularity: .month) }.count
    }

    static func restantes(hoy: Date = Date()) -> Int {
        max(0, porMes - usadas(hoy: hoy))
    }

    static func puedeGenerar(hoy: Date = Date()) -> Bool {
        restantes(hoy: hoy) > 0
    }

    // Se registra al generar, no al guardar: la llamada ya se ha pagado aunque el
    // usuario descarte el resultado.
    static func registrar(_ fecha: Date = Date()) {
        var todas = fechas()
        todas.append(fecha)
        // Solo interesa el mes en curso y el anterior; lo demás se poda.
        if let corte = cal.date(byAdding: .month, value: -1, to: fecha) {
            todas = todas.filter { $0 >= corte }
        }
        UserDefaults.standard.set(todas.map(\.timeIntervalSince1970), forKey: storageKey)
    }

    // Cuándo se renueva la cuota: el día 1 del mes siguiente.
    static func proximaRenovacion(hoy: Date = Date()) -> Date? {
        guard let inicioMes = cal.date(from: cal.dateComponents([.year, .month], from: hoy))
        else { return nil }
        return cal.date(byAdding: .month, value: 1, to: inicioMes)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func fechas() -> [Date] {
        let brutas = UserDefaults.standard.array(forKey: storageKey) as? [Double] ?? []
        return brutas.map { Date(timeIntervalSince1970: $0) }
    }
}
