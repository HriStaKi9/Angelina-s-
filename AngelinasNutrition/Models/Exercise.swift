import Foundation

/// One entry from the bundled exercise database (free-exercise-db, public domain).
/// Field names mirror the source JSON so `Resources/exercises.json` decodes directly.
struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let force: String?
    let level: Level
    let mechanic: String?
    let equipment: Equipment?
    let primaryMuscles: [Muscle]
    let secondaryMuscles: [Muscle]
    let instructions: [String]
    let category: Category
    let images: [String]

    static let imageBaseURL = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/")!

    var imageURLs: [URL] { images.map { Self.imageBaseURL.appendingPathComponent($0) } }
    var thumbnailURL: URL? { imageURLs.first }

    /// Missing equipment in the source data is almost always a bodyweight move or stretch.
    var resolvedEquipment: Equipment { equipment ?? .bodyOnly }

    var isCompound: Bool { mechanic == "compound" }

    func isAvailable(at location: TrainingLocation, homeEquipment: Set<Equipment>) -> Bool {
        switch location {
        case .gym: true
        case .home: resolvedEquipment == .bodyOnly || homeEquipment.contains(resolvedEquipment)
        }
    }
}

extension Exercise {
    enum Level: String, Codable, CaseIterable, Comparable {
        case beginner, intermediate, expert

        var title: String { rawValue.capitalized }
        private var rank: Int { Self.allCases.firstIndex(of: self)! }
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
    }

    enum Category: String, Codable, CaseIterable {
        case strength, stretching, plyometrics, powerlifting, cardio, strongman
        case olympicWeightlifting = "olympic weightlifting"

        var title: String { rawValue.capitalized }
    }

    enum Equipment: String, Codable, CaseIterable, Identifiable {
        case bodyOnly = "body only"
        case dumbbell, barbell, kettlebells, bands, cable, machine
        case medicineBall = "medicine ball"
        case exerciseBall = "exercise ball"
        case foamRoll = "foam roll"
        case ezCurlBar = "e-z curl bar"
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bodyOnly: "Bodyweight"
            case .ezCurlBar: "EZ Curl Bar"
            case .kettlebells: "Kettlebell"
            default: rawValue.capitalized
            }
        }

        var systemImage: String {
            switch self {
            case .bodyOnly: "figure.cross.training"
            case .dumbbell, .barbell, .ezCurlBar: "dumbbell.fill"
            case .kettlebells: "scalemass.fill"
            case .bands: "lasso"
            case .cable, .machine: "gearshape.2.fill"
            case .medicineBall, .exerciseBall: "circle.circle.fill"
            case .foamRoll: "cylinder.fill"
            case .other: "ellipsis.circle.fill"
            }
        }

        /// Equipment someone can realistically own at home; offered in onboarding.
        static let homeOptions: [Equipment] = [.dumbbell, .kettlebells, .bands, .exerciseBall, .medicineBall, .foamRoll, .barbell]
    }

    enum Muscle: String, Codable, CaseIterable, Identifiable {
        case abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes
        case hamstrings, lats, neck, quadriceps, shoulders, traps, triceps
        case lowerBack = "lower back"
        case middleBack = "middle back"

        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        var group: MuscleGroup {
            switch self {
            case .chest, .shoulders, .triceps: .push
            case .lats, .middleBack, .lowerBack, .traps, .biceps, .forearms, .neck: .pull
            case .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors: .legs
            case .abdominals: .core
            }
        }
    }

    enum MuscleGroup: String, CaseIterable, Identifiable {
        case push, pull, legs, core

        var id: String { rawValue }

        var title: String {
            switch self {
            case .push: "Chest & Shoulders"
            case .pull: "Back & Arms"
            case .legs: "Legs & Glutes"
            case .core: "Core"
            }
        }
    }
}

enum TrainingLocation: String, Codable, CaseIterable, Identifiable {
    case gym, home

    var id: String { rawValue }
    var title: String { self == .gym ? "Gym" : "Home" }
    var systemImage: String { self == .gym ? "building.2.fill" : "house.fill" }
}
