import Testing
import Foundation
@testable import Apex

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
