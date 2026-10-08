import Foundation

/// The coach-written personal plans bundled with the app.
final class PlanLibrary {
    static let shared = PlanLibrary()

    /// File names in the bundle (Xcode flattens `Resources/Plans/` into the bundle root).
    private static let planFiles = ["tsveti", "hristomir"]

    let plans: [PersonalPlan]

    init(bundle: Bundle = .main) {
        plans = Self.planFiles.compactMap { name in
            do {
                guard let url = bundle.url(forResource: name, withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try JSONDecoder().decode(PersonalPlan.self, from: Data(contentsOf: url))
            } catch {
                assertionFailure("Failed to load plan \(name).json: \(error)")
                return nil
            }
        }
    }

    func plan(id: String?) -> PersonalPlan? {
        guard let id else { return nil }
        return plans.first { $0.id == id }
    }
}
