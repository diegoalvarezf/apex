import Foundation
import SwiftUI

@MainActor
final class RoutineViewModel: ObservableObject {
    @Published var routines: [GymRoutine] = []
    @Published var isParsingAI = false
    @Published var aiError: String?

    // Rutina que el usuario está siguiendo ahora. Se guarda aparte del modelo para
    // no meter un campo en el JSON que produce la IA. Las demás quedan de archivo:
    // siguen consultables, pero no cuentan como entreno actual ni alimentan a la IA.
    @Published private(set) var activeRoutineID: UUID?

    var activeRoutine: GymRoutine? {
        routines.first { $0.id == activeRoutineID } ?? routines.first
    }

    func isActive(_ routine: GymRoutine) -> Bool {
        activeRoutine?.id == routine.id
    }

    func setActive(_ routine: GymRoutine) {
        activeRoutineID = routine.id
        UserDefaults.standard.set(routine.id.uuidString, forKey: activeKey)
    }

    private let storageKey = "apex_gym_routines_v1"
    private let activeKey = "apex_active_routine_id"

    init() { load() }

    // MARK: - Persistencia

    func save() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let raw = UserDefaults.standard.string(forKey: activeKey) {
            activeRoutineID = UUID(uuidString: raw)
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([GymRoutine].self, from: data) else { return }
        routines = saved
    }

    func delete(_ routine: GymRoutine) {
        routines.removeAll { $0.id == routine.id }
        // Si se borra la activa, pasa a serlo la primera que quede (activeRoutine ya
        // recurre a `routines.first`, pero se persiste para no depender del orden).
        if activeRoutineID == routine.id {
            activeRoutineID = routines.first?.id
            UserDefaults.standard.set(activeRoutineID?.uuidString, forKey: activeKey)
        }
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

    // MARK: - Cambiar un ejercicio suelto

    // Alternativa barata a regenerar la rutina cuando solo falla un ejercicio.
    // No consume cuota: cuesta una fracción de lo que cuesta rehacerla entera.
    func swapExercise(_ exercise: GymExercise, in day: GymDay, reason: String) async {
        isParsingAI = true
        aiError = nil
        defer { isParsingAI = false }

        do {
            let sustituto = try await ExerciseSwapper.swap(
                exercise: exercise, in: day, reason: reason)
            updateExercise(sustituto)
        } catch {
            aiError = error.localizedDescription
        }
    }

    // MARK: - Importar rutina con IA

    func parseRoutineWithAI(description: String) async {
        isParsingAI = true
        aiError = nil
        defer { isParsingAI = false }

        // Solo el texto que ha escrito el usuario: el esquema JSON y las reglas de
        // conversión los pone el servidor (catálogo cerrado), no el cliente.
        do {
            let raw = try await AIService.shared.analyze(.routineParse, input: description)

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
                // La recién importada pasa a ser la que se sigue; la anterior queda de archivo.
                setActive(parsed)
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
        // La cuota la lleva el servidor: es quien paga la llamada y el único que
        // no se puede manipular desde el móvil. Aquí no se comprueba nada por
        // adelantado —se intenta y, si está agotada, responde 429 y el error que
        // llega ya trae el límite y la fecha de renovación correctos.
        isParsingAI = true
        aiError = nil
        defer { isParsingAI = false }

        // Solo los datos —perfil/preferencias y contexto de salud—: el esquema JSON
        // y las reglas de diseño los pone el servidor, no el cliente.
        let datos = """
        PERFIL Y PREFERENCIAS DEL USUARIO:
        \(brief)

        CONTEXTO DE SALUD, ACTIVIDAD E HISTORIAL DE ENTRENAMIENTO:
        \(context)
        """

        do {
            let raw = try await AIService.shared.analyze(.routineCreate, input: datos)

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
                // La recién creada pasa a ser la que se sigue; la anterior queda de
                // archivo. Es lo que espera quien acaba de pedir una rutina nueva.
                setActive(parsed)
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
