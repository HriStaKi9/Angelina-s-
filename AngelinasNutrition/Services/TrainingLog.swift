import Foundation
import Observation

struct LoggedSet: Codable, Hashable {
    var weight: Double?
    var reps: Int?
    var seconds: Int?
    var done = false
}

struct LoggedExercise: Codable, Hashable, Identifiable {
    /// Position in the workout ("1", "5a"…), stable across sessions.
    let slot: String
    /// Which option was done: 0 = the plan's exercise, 1… = an alternative.
    let option: Int
    let name: Localized
    var sets: [LoggedSet]
    /// "More than 3 reps in reserve" – the plan's signal to add weight sooner.
    var feltEasy = false

    var id: String { slot }
    var doneSets: [LoggedSet] { sets.filter(\.done) }
    var topWeight: Double? { doneSets.compactMap(\.weight).max() }
    var lastDoneSet: LoggedSet? { doneSets.last }
}

struct WorkoutLog: Codable, Hashable, Identifiable {
    var id = UUID()
    let planID: String
    let workoutID: String
    let date: Date
    /// Program week (1-based) the session belongs to.
    let week: Int
    var isShort = false
    var isDeload = false
    var durationSeconds = 0
    var exercises: [LoggedExercise]
}

struct CheckIn: Codable, Hashable, Identifiable {
    var id = UUID()
    let planID: String
    var date: Date
    var weight: Double?
    var waist: Double?
    var hips: Double?
    var steps: Int?
    var flags: Set<CheckInFlag> = []

    func value(_ field: CheckInField) -> Double? {
        switch field {
        case .weight: weight
        case .waist: waist
        case .hips: hips
        case .steps: steps.map(Double.init)
        }
    }
}

/// Workout history, check-ins and chosen exercise options, persisted as one JSON file.
@Observable
final class TrainingLog {
    private struct Snapshot: Codable {
        var workouts: [WorkoutLog] = []
        var checkIns: [CheckIn] = []
        /// "planID/workoutID/slot" → chosen option index.
        var options: [String: Int] = [:]
    }

    private(set) var workouts: [WorkoutLog] = []
    private(set) var checkIns: [CheckIn] = []
    private var options: [String: Int] = [:]

    private let fileURL: URL?

    /// Pass `nil` for an in-memory log (previews, tests).
    init(fileURL: URL? = TrainingLog.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        workouts = snapshot.workouts
        checkIns = snapshot.checkIns
        options = snapshot.options
    }

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("training-log.json")
    }

    // MARK: Workouts

    func add(_ log: WorkoutLog) {
        workouts.append(log)
        save()
    }

    func delete(_ log: WorkoutLog) {
        workouts.removeAll { $0.id == log.id }
        save()
    }

    func workouts(planID: String) -> [WorkoutLog] {
        workouts.filter { $0.planID == planID }.sorted { $0.date > $1.date }
    }

    /// Past performances of one slot+option, newest first (with the session's week).
    func history(planID: String, workoutID: String, slot: String, option: Int) -> [(week: Int, date: Date, exercise: LoggedExercise)] {
        workouts(planID: planID)
            .filter { $0.workoutID == workoutID }
            .compactMap { log in
                log.exercises.first { $0.slot == slot && $0.option == option && !$0.doneSets.isEmpty }
                    .map { (log.week, log.date, $0) }
            }
    }

    func didTrain(planID: String, workoutID: String, on date: Date, calendar: Calendar = .current) -> Bool {
        workouts.contains { $0.planID == planID && $0.workoutID == workoutID && calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The plan says deload every 6–8 weeks; suggest one once 6+ weeks have passed since the last.
    func shouldSuggestDeload(planID: String, currentWeek: Int, every range: [Int]?) -> Bool {
        guard let minWeeks = range?.first else { return false }
        let lastDeloadWeek = workouts(planID: planID).first(where: \.isDeload)?.week ?? 0
        return currentWeek - lastDeloadWeek > minWeeks
    }

    // MARK: Exercise options

    func option(planID: String, workoutID: String, slot: String) -> Int {
        options["\(planID)/\(workoutID)/\(slot)"] ?? 0
    }

    func setOption(_ index: Int, planID: String, workoutID: String, slot: String) {
        options["\(planID)/\(workoutID)/\(slot)"] = index == 0 ? nil : index
        save()
    }

    // MARK: Check-ins

    func add(_ checkIn: CheckIn) {
        checkIns.append(checkIn)
        save()
    }

    func delete(_ checkIn: CheckIn) {
        checkIns.removeAll { $0.id == checkIn.id }
        save()
    }

    func checkIns(planID: String) -> [CheckIn] {
        checkIns.filter { $0.planID == planID }.sorted { $0.date > $1.date }
    }

    // MARK: Persistence

    // MARK: Account backup

    /// Everything this store keeps, for syncing to the account.
    func exportData() -> Data {
        (try? JSONEncoder().encode(Snapshot(workouts: workouts, checkIns: checkIns, options: options))) ?? Data()
    }

    /// Replaces local data with a backup from the account.
    func restore(from data: Data) {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        workouts = snapshot.workouts
        checkIns = snapshot.checkIns
        options = snapshot.options
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(workouts: workouts, checkIns: checkIns, options: options)
        do {
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save training log: \(error)")
        }
    }
}
