import Testing
import Foundation
@testable import Apex

// La cuota es lo que acota el coste por usuario: generar una rutina es la llamada
// más cara de la app. Si contara mal, un usuario podría gastar sin límite (o
// quedarse bloqueado sin motivo), así que se fija su comportamiento.
@MainActor
struct RoutineQuotaTests {

    private func limpio() { RoutineQuota.reset() }

    @Test func empiezaConLaCuotaEntera() {
        limpio()
        #expect(RoutineQuota.restantes() == RoutineQuota.porMes)
        #expect(RoutineQuota.puedeGenerar())
    }

    @Test func cadaGeneracionDescuentaUna() {
        limpio()
        RoutineQuota.registrar()
        #expect(RoutineQuota.usadas() == 1)
        #expect(RoutineQuota.restantes() == RoutineQuota.porMes - 1)
    }

    @Test func alAgotarlaYaNoSePuedeGenerar() {
        limpio()
        for _ in 0..<RoutineQuota.porMes { RoutineQuota.registrar() }
        #expect(RoutineQuota.restantes() == 0)
        #expect(!RoutineQuota.puedeGenerar())
    }

    // Lo que hace que sea "al mes" y no "para siempre": las del mes pasado no
    // cuentan. Sin esto la cuota se agotaría una vez y nunca se recuperaría.
    @Test func lasDelMesPasadoNoCuentan() {
        limpio()
        let mesPasado = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        for _ in 0..<RoutineQuota.porMes { RoutineQuota.registrar(mesPasado) }

        #expect(RoutineQuota.usadas() == 0)
        #expect(RoutineQuota.puedeGenerar())
    }

    // Se cuenta por mes natural, no por ventana de 30 días: la cuota se renueva el
    // día 1, que es lo que dice la interfaz.
    @Test func laRenovacionEsElPrimeroDelMesSiguiente() {
        let hoy = Date()
        guard let renovacion = RoutineQuota.proximaRenovacion(hoy: hoy) else {
            Issue.record("debería haber fecha de renovación"); return
        }
        let cal = Calendar.current
        #expect(cal.component(.day, from: renovacion) == 1)
        #expect(renovacion > hoy)
    }
}

// El sustituto llega como JSON dentro de la respuesta del modelo, que no siempre
// viene limpio. Estos tests fijan que se extraiga igual.
struct ExerciseSwapperTests {

    @Test func leeUnJSONLimpio() {
        let raw = #"{"name":"Press inclinado con mancuernas","sets":4,"reps":"8-10","muscleGroup":"Pecho","notes":"Menos estrés en el hombro"}"#
        let s = ExerciseSwapper.decode(raw)
        #expect(s?.name == "Press inclinado con mancuernas")
        #expect(s?.sets == 4)
        #expect(s?.muscleGroup == "Pecho")
    }

    // El caso real más frecuente: el modelo lo envuelve en un bloque de código.
    @Test func leeUnJSONEnvueltoEnMarkdown() {
        let raw = """
        ```json
        {"name":"Remo con mancuerna","sets":3,"reps":"10-12","muscleGroup":"Espalda","notes":"Alternativa sin barra"}
        ```
        """
        #expect(ExerciseSwapper.decode(raw)?.name == "Remo con mancuerna")
    }

    // O con una frase antes, pese a pedirle que no la ponga.
    @Test func leeUnJSONConTextoAlrededor() {
        let raw = "Te propongo este cambio:\n{\"name\":\"Fondos en paralelas\",\"sets\":3,\"reps\":\"al fallo\",\"muscleGroup\":\"Tríceps\",\"notes\":\"Sin material extra\"}\nEspero que encaje."
        #expect(ExerciseSwapper.decode(raw)?.name == "Fondos en paralelas")
    }

    // Si no hay JSON, devuelve nil para que la vista muestre el error en vez de
    // sustituir el ejercicio por algo inventado.
    @Test func sinJSONDevuelveNada() {
        #expect(ExerciseSwapper.decode("No he podido proponer un sustituto.") == nil)
    }
}
