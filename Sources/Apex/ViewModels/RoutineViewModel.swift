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
}
