import Foundation
import Observation

/// Daily food log, recent foods and a custom calorie goal, persisted as one JSON file.
@Observable
final class FoodDiaryStore {
    private struct Snapshot: Codable {
        var entries: [DiaryEntry] = []
        var recents: [FoodItem] = []
        var goals: [String: CalorieGoal] = [:]
    }

    private(set) var entries: [DiaryEntry] = []
    private(set) var recents: [FoodItem] = []
    /// Custom goal per plan id ("" = no plan); falls back to the plan's targets.
    private var goals: [String: CalorieGoal] = [:]
    private let fileURL: URL?
    /// Called after an entry is added or deleted (used to mirror the diary into Apple Health).
    @ObservationIgnored var onAdd: ((DiaryEntry) -> Void)?
    @ObservationIgnored var onDelete: ((DiaryEntry) -> Void)?

    init(fileURL: URL? = FoodDiaryStore.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        entries = snapshot.entries
        recents = snapshot.recents
        goals = snapshot.goals
    }

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("food-diary.json")
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Entries

    func entries(on date: Date, course: Meal.Course? = nil) -> [DiaryEntry] {
        let key = Self.dayKey(date)
        return entries.filter { $0.day == key && (course == nil || $0.course == course) }
    }

    func totals(on date: Date, course: Meal.Course? = nil) -> Nutrients {
        entries(on: date, course: course).reduce(.zero) { $0 + $1.nutrients }
    }

    func add(_ entry: DiaryEntry) {
        entries.append(entry)
        onAdd?(entry)
        if let food = entry.food {
            var food = food
            if let grams = entry.grams { food.portion = grams }
            recents.removeAll { $0.id == food.id }
            recents.insert(food, at: 0)
            recents = Array(recents.prefix(30))
        }
        save()
    }

    func delete(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        onDelete?(entry)
        save()
    }

    func logPlanMeal(_ meal: Meal, portion: Double = 1, on date: Date) {
        let nutrients = Nutrients(kcal: Double(meal.kcal.lower + meal.kcal.upper) / 2,
                                  protein: Double(meal.protein.lower + meal.protein.upper) / 2,
                                  carbs: nil, fat: nil) * portion
        let detail = portion == 1 ? nil : "× \(portion.formatted(.number.precision(.fractionLength(0...1))))"
        add(DiaryEntry(day: Self.dayKey(date), course: meal.course,
                       name: Localized(bg: "№\(meal.number) \(meal.name.bg)", en: "#\(meal.number) \(meal.name.en)"),
                       detail: detail, nutrients: nutrients, planMealID: meal.id))
    }

    func isLogged(_ meal: Meal, on date: Date) -> Bool {
        entries(on: date).contains { $0.planMealID == meal.id }
    }

    // MARK: Goal

    /// Custom goal if set, otherwise the middle of the plan's kcal and protein ranges.
    func goal(for plan: PersonalPlan?) -> CalorieGoal {
        if let custom = goals[plan?.id ?? ""] { return custom }
        guard let n = plan?.nutrition else { return CalorieGoal(kcal: 2000, protein: nil) }
        return CalorieGoal(kcal: (n.kcal.lower + n.kcal.upper) / 2, protein: (n.protein.lower + n.protein.upper) / 2)
    }

    func hasCustomGoal(for plan: PersonalPlan?) -> Bool { goals[plan?.id ?? ""] != nil }

    func setGoal(_ goal: CalorieGoal?, for plan: PersonalPlan?) {
        goals[plan?.id ?? ""] = goal
        save()
    }

    // MARK: Account backup

    /// Everything this store keeps, for syncing to the account.
    func exportData() -> Data {
        (try? JSONEncoder().encode(Snapshot(entries: entries, recents: recents, goals: goals))) ?? Data()
    }

    /// Replaces local data with a backup from the account.
    func restore(from data: Data) {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        entries = snapshot.entries
        recents = snapshot.recents
        goals = snapshot.goals
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(entries: entries, recents: recents, goals: goals)
        try? JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }
}

/// Built-in basic foods (`Resources/basic-foods.json`), approximate values per 100 g raw/dry.
enum BasicFoods {
    static let all: [FoodItem] = {
        guard let url = Bundle.main.url(forResource: "basic-foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let foods = try? JSONDecoder().decode([FoodItem].self, from: data) else { return [] }
        return foods
    }()

    static func search(_ query: String) -> [FoodItem] {
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.bg.localizedCaseInsensitiveContains(query) || $0.name.en.localizedCaseInsensitiveContains(query) }
    }
}
