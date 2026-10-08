import Foundation

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var goal: FitnessGoal = .tone
    var location: TrainingLocation = .home
    var homeEquipment: Set<Exercise.Equipment> = [.dumbbell, .bands]
    var level: Exercise.Level = .beginner
    var sessionsPerWeek: Int = 3

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? ""
    }
}

/// The nutrition goal drives both the eating plan and the shape of each workout.
enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case loseFat, tone, buildMuscle, maintain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loseFat: "Lose fat"
        case .tone: "Tone & sculpt"
        case .buildMuscle: "Build muscle"
        case .maintain: "Stay healthy"
        }
    }

    var subtitle: String {
        switch self {
        case .loseFat: "Calorie deficit with circuits that keep your heart rate up"
        case .tone: "Slight deficit, high-rep strength work for definition"
        case .buildMuscle: "Calorie surplus with heavier compound lifts"
        case .maintain: "Balanced eating and full-body sessions"
        }
    }

    var systemImage: String {
        switch self {
        case .loseFat: "flame.fill"
        case .tone: "sparkles"
        case .buildMuscle: "dumbbell.fill"
        case .maintain: "heart.fill"
        }
    }

    /// How the eating plan translates into training: sets, reps and rest.
    var prescription: Prescription {
        switch self {
        case .loseFat: Prescription(sets: 3, reps: "12–15", restSeconds: 30, style: "Circuit — move straight to the next exercise")
        case .tone: Prescription(sets: 3, reps: "10–15", restSeconds: 45, style: "Supersets — pair moves back to back")
        case .buildMuscle: Prescription(sets: 4, reps: "6–10", restSeconds: 90, style: "Straight sets — rest fully between sets")
        case .maintain: Prescription(sets: 3, reps: "10–12", restSeconds: 60, style: "Straight sets at a steady pace")
        }
    }
}

struct Prescription: Equatable {
    let sets: Int
    let reps: String
    let restSeconds: Int
    let style: String
}
