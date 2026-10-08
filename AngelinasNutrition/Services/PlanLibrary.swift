import Foundation
import Observation

/// Personal plans: the coach-written ones bundled with the app plus plans imported from PDF.
/// An imported plan with the same id as a bundled one replaces it (e.g. a new eating plan for Tsveti).
@Observable
final class PlanLibrary {
    static let shared = PlanLibrary()

    /// File names in the bundle (Xcode flattens `Resources/Plans/` into the bundle root).
    private static let planFiles = ["tsveti", "hristomir"]

    private let bundled: [PersonalPlan]
    private(set) var imported: [PersonalPlan] = []
    private let directory: URL?

    var plans: [PersonalPlan] {
        bundled.map { plan in imported.first { $0.id == plan.id } ?? plan }
            + imported.filter { plan in !bundled.contains { $0.id == plan.id } }
    }

    init(bundle: Bundle = .main, directory: URL? = PlanLibrary.defaultDirectory) {
        bundled = Self.planFiles.compactMap { name in
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
        self.directory = directory
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        imported = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PersonalPlan.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.en < $1.name.en }
    }

    static var defaultDirectory: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let url = base.appendingPathComponent("ImportedPlans", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func plan(id: String?) -> PersonalPlan? {
        guard let id else { return nil }
        return plans.first { $0.id == id }
    }

    func isBundled(_ id: String) -> Bool { bundled.contains { $0.id == id } }
    func isImported(_ id: String) -> Bool { imported.contains { $0.id == id } }

    func save(_ plan: PersonalPlan) throws {
        imported.removeAll { $0.id == plan.id }
        imported.append(plan)
        if let directory {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(plan).write(to: directory.appendingPathComponent("\(plan.id).json"), options: .atomic)
        }
    }

    /// Removes an imported plan; for a bundled id this restores the coach's original.
    func removeImported(id: String) {
        imported.removeAll { $0.id == id }
        if let directory { try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json")) }
    }

    /// Replaces all imported plans (used when restoring from an account).
    func replaceImported(with plans: [PersonalPlan]) {
        for plan in imported where !plans.contains(where: { $0.id == plan.id }) { removeImported(id: plan.id) }
        for plan in plans { try? save(plan) }
    }
}
