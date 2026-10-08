import Foundation

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var goal: FitnessGoal = .tone
    var location: TrainingLocation = .home
    var homeEquipment: Set<Exercise.Equipment> = [.dumbbell, .bands]
    var level: Exercise.Level = .beginner
    var sessionsPerWeek: Int = 3
    /// Active personal plan (`PersonalPlan.id`); nil means the app builds a generic plan from the goal.
    /// Optional so profiles saved before plans existed still decode.
    var planID: String?
    /// Monday the training program started on; drives "Week N" and A/B rotation.
    var programStart: Date?
    var language: ContentLanguage?
    /// Training equipment for the "more exercises" section; nil = the default home-gym set.
    var gear: Set<HomeGear>?
    /// A recommended program the user started; replaces the coach's training program until removed.
    var recommendedProgram: RecommendedProgram?
    /// App look: nil = automatic (Steel for a male plan, otherwise Rose).
    var theme: ThemeVariant?
    /// The user's changes to program schedules, keyed by `ProfileStore.scheduleKey`.
    var scheduleEdits: [String: ScheduleEdits]?

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

struct RecommendedProgram: Codable, Equatable {
    let goal: FitnessGoal
    let sessionsPerWeek: Int
    let program: TrainingProgram
}

/// Moves and swaps in a program's week: permanent ones replace the program's rotation,
/// one-off ones replace a single program week (1-based).
struct ScheduleEdits: Codable, Equatable {
    var everyWeek: [[ScheduleDay]]?
    var weeks: [Int: [ScheduleDay]] = [:]
}
