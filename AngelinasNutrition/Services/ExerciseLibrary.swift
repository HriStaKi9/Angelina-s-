import Foundation

/// Read-only access to the bundled exercise database.
final class ExerciseLibrary {
    static let shared = ExerciseLibrary()

    let exercises: [Exercise]
    private let byID: [String: Exercise]

    init(bundle: Bundle = .main) {
        do {
            guard let url = bundle.url(forResource: "exercises", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            exercises = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            assertionFailure("Failed to load exercises.json: \(error)")
            exercises = []
        }
        byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    func exercise(id: String) -> Exercise? { byID[id] }

    func available(for profile: UserProfile) -> [Exercise] {
        exercises.filter { $0.isAvailable(at: profile.location, homeEquipment: profile.homeEquipment) }
    }
}
