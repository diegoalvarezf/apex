import Foundation

// Estimación del VO2max a partir de carreras, para cuando el reloj no lo escribe
// en Apple Salud.
//
// Es la misma idea que usan Garmin/Suunto (Firstbeat): mirar qué ritmo sostienes a
// qué frecuencia cardíaca y extrapolar al esfuerzo máximo. El algoritmo concreto de
// Firstbeat es propietario y no está publicado, así que aquí se combinan dos
// ecuaciones que sí lo están:
//
// 1. Coste de oxígeno de correr (ACSM Guidelines, ecuación metabólica de carrera):
//      VO2 = 0.2 · velocidad(m/min) + 0.9 · velocidad · pendiente + 3.5
//
// 2. Equivalencia %reserva de FC ≈ %reserva de VO2 (Swain & Leutholtz 1997), que
//    permite extrapolar de una carrera submáxima al máximo:
//      (VO2 − VO2reposo) / (VO2max − VO2reposo) = (FC − FCreposo) / (FCmáx − FCreposo)
//    despejando:  VO2max = VO2reposo + (VO2 − VO2reposo) / HRr
//
// Solo se usan carreras donde la extrapolación tiene sentido (ver `isUsable`).
enum VO2MaxEstimator {

    // VO2 en reposo: 1 MET = 3.5 ml/kg/min (convención de la propia ecuación ACSM)
    static let restingVO2 = 3.5

    static let runTypes: Set<String> = ["run", "trail_run", "trailrun", "virtualrun"]

    // Coste de oxígeno de correr a una velocidad dada, en ml/kg/min.
    // `grade` es la pendiente en tanto por uno (0.02 = 2%).
    static func vo2AtPace(metersPerMinute: Double, grade: Double = 0) -> Double {
        0.2 * metersPerMinute + 0.9 * metersPerMinute * grade + restingVO2
    }

    // ¿Sirve esta actividad para estimar?
    //
    // La extrapolación asume estado estacionario, así que se descartan las sesiones
    // de ritmo variable y las demasiado cortas (la FC aún está subiendo). También se
    // exige una intensidad intermedia: por debajo del 50% de la reserva el error se
    // dispara al multiplicar, y por encima del 95% ya no queda margen que extrapolar.
    static func isUsable(_ act: StravaActivity, restingHR: Double, maxHR: Double) -> Bool {
        guard runTypes.contains(act.sportType.lowercased()) else { return false }
        guard !act.isStructuredWorkout else { return false }
        guard act.movingTime >= 15 * 60 else { return false }
        guard act.distance >= 2_000 else { return false }
        guard let hr = act.averageHeartrate, maxHR > restingHR else { return false }

        // Desnivel medio por encima del 2% (subida o bajada): el coste de oxígeno
        // deja de corresponder al ritmo llano y la ecuación se desvía.
        guard act.distance > 0, act.totalElevationGain / act.distance <= 0.02 else { return false }

        let hrr = (hr - restingHR) / (maxHR - restingHR)
        return hrr >= 0.50 && hrr <= 0.95
    }

    // Pendiente media que se le pasa a la ecuación del ACSM.
    //
    // Strava da el desnivel POSITIVO acumulado, no el neto, así que esto no es la
    // pendiente real de ningún tramo: reparte el coste de subir a lo largo de toda la
    // distancia. Y no se descuenta nada por las bajadas a propósito — bajar cuesta
    // menos que el llano, pero no devuelve lo que costó subir, y la ecuación del ACSM
    // solo está validada para pendientes positivas. Aplicar la pendiente con signo
    // haría que subir y bajar se anulasen, que es justo lo que no ocurre corriendo.
    static func averageGrade(_ act: StravaActivity) -> Double {
        guard act.distance > 0 else { return 0 }
        return act.totalElevationGain / act.distance
    }

    // VO2max que implica una carrera concreta. nil si la actividad no sirve.
    static func estimate(from act: StravaActivity, restingHR: Double, maxHR: Double) -> Double? {
        guard isUsable(act, restingHR: restingHR, maxHR: maxHR),
              let hr = act.averageHeartrate else { return nil }

        let metersPerMinute = act.distance / (Double(act.movingTime) / 60.0)
        let vo2 = vo2AtPace(metersPerMinute: metersPerMinute, grade: averageGrade(act))
        let hrr = (hr - restingHR) / (maxHR - restingHR)
        let vo2max = restingVO2 + (vo2 - restingVO2) / hrr

        // Fuera del rango humano plausible se descarta: es señal de que algún dato
        // de entrada (FCmáx, FC reposo o el GPS) no era bueno.
        guard vo2max >= 20, vo2max <= 90 else { return nil }
        return vo2max
    }

    // Un punto por carrera válida: la estimación que implica cada rodaje, en su fecha.
    // Es la serie que hay detrás del valor mostrado (que es su mediana), y permite
    // ver la evolución sin inventar una interpolación entre sesiones.
    static func series(
        from activities: [StravaActivity],
        restingHR: Double,
        maxHR: Double,
        days: Int = 90
    ) -> [MetricSample] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return activities
            .filter { $0.startDate >= cutoff }
            .compactMap { act in
                estimate(from: act, restingHR: restingHR, maxHR: maxHR)
                    .map { MetricSample(date: act.startDate, value: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    // Estimación global: mediana de las carreras válidas de los últimos `days` días.
    //
    // Mediana y no media ni máximo: un GPS que se va o una carrera con el pulsómetro
    // saltando producen valores extremos, y la mediana no se mueve por ellos. El
    // máximo, en cambio, elegiría precisamente el peor dato.
    static func estimate(
        from activities: [StravaActivity],
        restingHR: Double,
        maxHR: Double,
        days: Int = 90,
        minimumRuns: Int = 3
    ) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let values = activities
            .filter { $0.startDate >= cutoff }
            .compactMap { estimate(from: $0, restingHR: restingHR, maxHR: maxHR) }
            .sorted()

        // Con una o dos carreras la mediana no filtra nada: mejor no dar cifra.
        guard values.count >= minimumRuns else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }
}
