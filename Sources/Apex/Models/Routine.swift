import SwiftUI

struct GymExercise: Codable, Identifiable {
    var id: UUID
    var name: String
    var sets: Int
    var reps: String
    var weight: String
    var notes: String
    var muscleGroup: String

    var supersetGroup: String?   // "A", "B", "C"… — nil si no es superserie

    init(id: UUID = UUID(), name: String, sets: Int, reps: String,
         weight: String = "", notes: String = "", muscleGroup: String = "", supersetGroup: String? = nil) {
        self.id = id; self.name = name; self.sets = sets; self.reps = reps
        self.weight = weight; self.notes = notes; self.muscleGroup = muscleGroup
        self.supersetGroup = supersetGroup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        if let v = try? c.decode(Int.self, forKey: .sets) { sets = v }
        else if let s = try? c.decode(String.self, forKey: .sets), let v = Int(s) { sets = v }
        else { sets = 3 }
        if let v = try? c.decode(String.self, forKey: .reps) { reps = v }
        else if let v = try? c.decode(Int.self, forKey: .reps) { reps = "\(v)" }
        else { reps = "8-12" }
        weight       = (try? c.decode(String.self,  forKey: .weight))       ?? ""
        notes        = (try? c.decode(String.self,  forKey: .notes))        ?? ""
        muscleGroup  = (try? c.decode(String.self,  forKey: .muscleGroup))  ?? ""
        supersetGroup = try? c.decode(String.self, forKey: .supersetGroup)
    }
}

struct GymDay: Codable, Identifiable {
    var id: UUID
    var name: String
    var shortName: String
    var exercises: [GymExercise]
    var notes: String

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    var muscleGroups: [String] { Array(Set(exercises.map(\.muscleGroup))).sorted() }

    init(id: UUID = UUID(), name: String, shortName: String,
         exercises: [GymExercise], notes: String = "") {
        self.id = id; self.name = name; self.shortName = shortName
        self.exercises = exercises; self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name      = try c.decode(String.self, forKey: .name)
        shortName = (try? c.decode(String.self, forKey: .shortName)) ?? name
        exercises = (try? c.decode([GymExercise].self, forKey: .exercises)) ?? []
        notes     = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }
}

struct GymRoutine: Codable, Identifiable {
    var id: UUID
    var name: String
    var days: [GymDay]
    var aiSummary: String
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, days: [GymDay],
         aiSummary: String = "", updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.days = days
        self.aiSummary = aiSummary; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name      = try c.decode(String.self, forKey: .name)
        days      = (try? c.decode([GymDay].self, forKey: .days)) ?? []
        aiSummary = (try? c.decode(String.self, forKey: .aiSummary)) ?? ""
        updatedAt = (try? c.decode(Date.self,   forKey: .updatedAt)) ?? Date()
    }
}
