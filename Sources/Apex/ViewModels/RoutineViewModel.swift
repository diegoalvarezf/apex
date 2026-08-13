import Foundation
import SwiftUI

@MainActor
final class RoutineViewModel: ObservableObject {
    @Published var routines: [GymRoutine] = []
    @Published var isParsingAI = false
    @Published var aiError: String?

    private let storageKey = "apex_gym_routines_v1"

    init() { load() }

    // MARK: - Persistencia

    func save() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([GymRoutine].self, from: data) else { return }
        routines = saved
    }

    func delete(_ routine: GymRoutine) {
        routines.removeAll { $0.id == routine.id }
        save()
    }

    // Actualiza un ejercicio (por id, estable) en cualquier rutina/día y persiste.
    // El id no cambia, así que el historial de progresión (RoutineProgressStore) se conserva.
    func updateExercise(_ updated: GymExercise) {
        for ri in routines.indices {
            for di in routines[ri].days.indices {
                if let ei = routines[ri].days[di].exercises.firstIndex(where: { $0.id == updated.id }) {
                    routines[ri].days[di].exercises[ei] = updated
                    routines[ri].updatedAt = Date()
                    save()
                    return
                }
            }
        }
    }

    // MARK: - Importar rutina con IA

    func parseRoutineWithAI(description: String) async {
        isParsingAI = true
        aiError = nil
        defer { isParsingAI = false }

        let systemPrompt = """
        Eres un parser de rutinas de gimnasio. Tu única función es convertir texto libre en JSON válido.
        Responde SOLO con el objeto JSON, sin markdown, sin backticks, sin texto antes ni después.
        El JSON debe empezar con { y terminar con }.
        """

        let userPrompt = """
        Convierte esta rutina de gimnasio en JSON con la siguiente estructura exacta:

        {
          "name": "Nombre corto de la rutina",
          "aiSummary": "Resumen de 1-2 frases",
          "updatedAt": "2024-01-01T00:00:00Z",
          "days": [
            {
              "name": "Día A – Pecho y Tríceps",
              "shortName": "Pecho",
              "notes": "",
              "exercises": [
                {
                  "name": "Press banca",
                  "sets": 4,
                  "reps": "8-10",
                  "weight": "70kg",
                  "notes": "",
                  "muscleGroup": "Pecho",
                  "supersetGroup": null
                }
              ]
            }
          ]
        }

        Reglas:
        - sets SIEMPRE como número entero (ej: 4, no "4")
        - reps como texto (ej: "8-10", "al fallo", "30s")
        - weight: el peso si se menciona, si no ""
        - muscleGroup: Pecho, Espalda, Hombros, Bíceps, Tríceps, Piernas, Core, Glúteos, Cardio
        - shortName: 1-2 palabras para la pestaña de navegación
        - Si el usuario no diferencia días, pon todo en un único día
        - supersetGroup: si dos o más ejercicios se hacen en superserie juntos, asígnales la misma letra ("A", "B", "C"…). Si no hay superserie, usa null. Cada grupo distinto de superserie lleva una letra diferente.

        Rutina a parsear:
        \(description)
        """

        do {
            let raw = try await AIService.shared.rawCompletion(prompt: userPrompt, system: systemPrompt)

            // Extrae el bloque JSON aunque Claude añada texto extra
            guard let jsonString = AIService.extractJSON(from: raw) else {
                aiError = "La IA no devolvió un JSON válido. Inténtalo de nuevo o simplifica la descripción."
                return
            }

            guard let data = jsonString.data(using: .utf8) else {
                aiError = "Error al procesar la respuesta."
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                var parsed = try decoder.decode(GymRoutine.self, from: data)
                parsed.updatedAt = Date()
                routines.insert(parsed, at: 0)
                save()
            } catch {
                // Muestra qué devolvió Claude para facilitar el diagnóstico
                let preview = String(jsonString.prefix(200))
                aiError = "No pude parsear la rutina (\(error.localizedDescription)).\nRespuesta: \(preview)"
            }

        } catch {
            aiError = "Error de red: \(error.localizedDescription)"
        }
    }

    // MARK: - Crear rutina desde cero con IA (Opus)

    // `brief` = respuestas del cuestionario; `context` = métricas de salud, historial
    // y pesos ya registrados (montado por la vista). La IA diseña la rutina y la
    // devuelve en el MISMO esquema JSON que el parser.
    func createRoutineWithAI(brief: String, context: String) async {
        isParsingAI = true
        aiError = nil
        defer { isParsingAI = false }

        let systemPrompt = """
        Eres un entrenador de fuerza titulado. Diseñas rutinas de gimnasio seguras y
        efectivas basándote en principios reconocidos de la ciencia del entrenamiento:
        - Sobrecarga progresiva y periodización.
        - Volumen semanal por grupo muscular en el rango de hipertrofia (aprox. 10-20 series
          efectivas/semana por grupo para intermedios), ajustado al nivel del usuario.
        - Frecuencia de 2x/semana por grupo cuando el número de días lo permita.
        - Selección de ejercicios: básicos multiarticulares primero, accesorios después.
        - Rangos de repeticiones acordes al objetivo (fuerza 3-6, hipertrofia 6-12, resistencia 12-20).
        - Respeta lesiones/limitaciones y el material disponible.
        - Si el historial muestra la progresión de un ejercicio, úsala: propón el siguiente
          paso sobre el último peso registrado. Si un ejercicio lleva varias sesiones sin
          moverse, no repitas "sube peso": cambia el rango de repeticiones, descarga o
          sustituye el ejercicio por otro del mismo patrón.
        - Si se indica qué grupos se han trabajado los últimos 7 días, reparte la frecuencia
          teniéndolo en cuenta en vez de recargar lo que ya viene cargado.
        - Ajusta el volumen a la recuperación y al sueño: con la carga alta (ACWR elevado) o
          varias noches durmiendo poco, no propongas la semana más exigente.

        Responde SOLO con el objeto JSON, sin markdown, sin backticks, sin texto antes ni
        después. El JSON debe empezar con { y terminar con }.
        """

        let userPrompt = """
        Diseña una rutina de gimnasio personalizada y devuélvela en este esquema EXACTO:

        {
          "name": "Nombre corto de la rutina",
          "aiSummary": "Resumen de 1-2 frases: objetivo, estructura y progresión",
          "updatedAt": "2024-01-01T00:00:00Z",
          "days": [
            {
              "name": "Día A – Pecho y Tríceps",
              "shortName": "Pecho",
              "notes": "Nota opcional del día",
              "exercises": [
                {
                  "name": "Press banca",
                  "sets": 4,
                  "reps": "6-8",
                  "weight": "",
                  "notes": "Técnica/tempo/descanso si aplica",
                  "muscleGroup": "Pecho",
                  "supersetGroup": null
                }
              ]
            }
          ]
        }

        Reglas del JSON:
        - sets SIEMPRE número entero. reps como texto ("6-8", "al fallo", "30s").
        - weight: "" salvo que el historial permita sugerir un peso concreto de partida.
        - muscleGroup: Pecho, Espalda, Hombros, Bíceps, Tríceps, Piernas, Core, Glúteos, Cardio.
        - supersetGroup: misma letra ("A","B"…) para ejercicios en superserie; null si no.
        - shortName: 1-2 palabras para la pestaña.

        Perfil y preferencias del usuario:
        \(brief)

        Contexto de salud, actividad e historial de entrenamiento:
        \(context)
        """

        do {
            let raw = try await AIService.shared.rawCompletion(
                prompt: userPrompt, system: systemPrompt,
                model: ClaudeConfig.opusModel, maxTokens: 8000)

            guard let jsonString = AIService.extractJSON(from: raw) else {
                aiError = "La IA no devolvió un JSON válido. Inténtalo de nuevo."
                return
            }
            guard let data = jsonString.data(using: .utf8) else {
                aiError = "Error al procesar la respuesta."
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                var parsed = try decoder.decode(GymRoutine.self, from: data)
                parsed.updatedAt = Date()
                routines.insert(parsed, at: 0)
                save()
            } catch {
                let preview = String(jsonString.prefix(200))
                aiError = "No pude parsear la rutina (\(error.localizedDescription)).\nRespuesta: \(preview)"
            }
        } catch {
            aiError = "Error creando la rutina: \(error.localizedDescription)"
        }
    }
}
