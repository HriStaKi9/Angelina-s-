import Foundation
import Observation

// MARK: - Catalog

struct GroceryItem: Codable, Hashable, Identifiable {
    enum Aisle: String, Codable, CaseIterable {
        case meat, fish, dairy, produce, grains, pantry

        var title: Localized {
            switch self {
            case .meat: Localized(bg: "Месо", en: "Meat")
            case .fish: Localized(bg: "Риба", en: "Fish")
            case .dairy: Localized(bg: "Яйца и млечни", en: "Eggs & dairy")
            case .produce: Localized(bg: "Плодове и зеленчуци", en: "Fruit & vegetables")
            case .grains: Localized(bg: "Зърнени и хляб", en: "Grains & bread")
            case .pantry: Localized(bg: "Други", en: "Pantry")
            }
        }

        var systemImage: String {
            switch self {
            case .meat: "fork.knife"
            case .fish: "fish.fill"
            case .dairy: "cup.and.saucer.fill"
            case .produce: "carrot.fill"
            case .grains: "takeoutbag.and.cup.and.straw.fill"
            case .pantry: "cabinet.fill"
            }
        }
    }

    let key: String
    let name: Localized
    let aisle: Aisle

    var id: String { key }
}

/// Products the shopping list groups ingredients into (`Resources/grocery-catalog.json`).
final class GroceryCatalog {
    static let shared = GroceryCatalog()

    let items: [String: GroceryItem]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "grocery-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([GroceryItem].self, from: data) else {
            assertionFailure("Failed to load grocery-catalog.json")
            items = [:]
            return
        }
        items = Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
    }

    init(items: [GroceryItem]) {
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
    }
}

// MARK: - Calculator

struct GroceryLine: Hashable, Identifiable {
    let item: GroceryItem
    let unit: ShopAmount.Unit
    let quantity: Double
    /// How many selected meals use this product.
    let mealCount: Int

    var id: String { "\(item.key)-\(unit.rawValue)" }

    /// "1.2 кг", "450 г", "1 л", "11 бр." – rounded up to something you can actually buy.
    func amount(_ language: ContentLanguage) -> String {
        let bg = language == .bg
        switch unit {
        case .g:
            return quantity >= 1000 ? "\(Self.roundedThousands(quantity)) \(bg ? "кг" : "kg")" : "\(Self.roundedSmall(quantity)) \(bg ? "г" : "g")"
        case .ml:
            return quantity >= 1000 ? "\(Self.roundedThousands(quantity)) \(bg ? "л" : "L")" : "\(Self.roundedSmall(quantity)) \(bg ? "мл" : "ml")"
        case .pcs:
            return "\(Int(quantity.rounded(.up))) \(bg ? "бр." : "pcs")"
        }
    }

    /// Round up so the list never under-buys: 1020 g → 1.1 kg.
    private static func roundedThousands(_ value: Double) -> String {
        ((value / 100).rounded(.up) / 10).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// 15 → 15, 112 → 120: steps of 5 under 100 g, of 10 above.
    private static func roundedSmall(_ value: Double) -> Int {
        let step: Double = value < 100 ? 5 : 10
        return Int((value / step).rounded(.up) * step)
    }
}

struct GroceryList: Equatable {
    let lines: [GroceryLine]
    /// Ingredient lines without an amount (spices, herbs, garnish), de-duplicated.
    let toTaste: [Localized]
    let mealCount: Int

    func lines(in aisle: GroceryItem.Aisle) -> [GroceryLine] {
        lines.filter { $0.item.aisle == aisle }
    }
}

enum GroceryCalculator {
    /// Sums every ingredient of the chosen meals for the chosen days, across one or more people's plans.
    static func list(for weeks: [(plan: NutritionPlan, days: [DayMenu])], catalog: GroceryCatalog) -> GroceryList {
        var totals: [String: (item: GroceryItem, unit: ShopAmount.Unit, qty: Double, meals: Int)] = [:]
        var toTaste: [Localized] = []
        var mealCount = 0

        for (plan, days) in weeks {
            for day in days {
                for meal in day.meals(in: plan) {
                    mealCount += 1
                    var countedForMeal: Set<String> = []
                    for ingredient in meal.ingredients {
                        guard let amounts = ingredient.shop else {
                            if !toTaste.contains(ingredient.text) { toTaste.append(ingredient.text) }
                            continue
                        }
                        for amount in amounts {
                            guard let item = catalog.items[amount.item] else { continue }
                            let key = "\(amount.item)-\(amount.unit.rawValue)"
                            var entry = totals[key] ?? (item, amount.unit, 0, 0)
                            entry.qty += amount.qty
                            if countedForMeal.insert(key).inserted { entry.meals += 1 }
                            totals[key] = entry
                        }
                    }
                }
            }
        }

        let lines = totals.values
            .map { GroceryLine(item: $0.item, unit: $0.unit, quantity: $0.qty, mealCount: $0.meals) }
            .sorted { $0.item.name.bg.localizedCompare($1.item.name.bg) == .orderedAscending }
        return GroceryList(lines: lines, toTaste: toTaste, mealCount: mealCount)
    }

    /// Plain-text list for sharing (Messages, Notes, a shopping app…).
    static func text(_ list: GroceryList, language: ContentLanguage, title: String) -> String {
        var out = [title, ""]
        for aisle in GroceryItem.Aisle.allCases {
            let lines = list.lines(in: aisle)
            guard !lines.isEmpty else { continue }
            out.append(aisle.title[language].uppercased())
            out += lines.map { "• \($0.item.name[language]) – \($0.amount(language))" }
            out.append("")
        }
        if !list.toTaste.isEmpty {
            out.append(language == .bg ? "ПО ВКУС" : "TO TASTE")
            out.append(list.toTaste.map { $0[language] }.joined(separator: ", "))
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - The user's week

/// Which meal options each person plans to eat each day, plus grocery-list settings.
/// Starts from the plan's sample week; every option from the plan can be picked.
@Observable
final class WeekMenuStore {
    private struct Snapshot: Codable {
        var weeks: [String: [DayMenu]] = [:]
        var groceryPlanIDs: Set<String>?
        var groceryDays: Set<Int>?
        var checked: Set<String> = []
    }

    private var weeks: [String: [DayMenu]] = [:]
    /// Whose weeks go into the shopping list; nil = just the active plan.
    var groceryPlanIDs: Set<String>? { didSet { save() } }
    var groceryDays: Set<Int> = Set(1...7) { didSet { save() } }
    /// Shopping-list lines ticked off in the shop.
    private(set) var checked: Set<String> = []

    private let fileURL: URL?

    init(fileURL: URL? = WeekMenuStore.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        weeks = snapshot.weeks
        groceryPlanIDs = snapshot.groceryPlanIDs
        groceryDays = snapshot.groceryDays ?? Set(1...7)
        checked = snapshot.checked
    }

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("week-menus.json")
    }

    func week(for plan: PersonalPlan) -> [DayMenu] {
        weeks[plan.id] ?? plan.nutrition.week
    }

    func menu(for plan: PersonalPlan, weekday: Int) -> DayMenu? {
        week(for: plan).first { $0.weekday == weekday }
    }

    func isCustomized(_ plan: PersonalPlan) -> Bool { weeks[plan.id] != nil && weeks[plan.id] != plan.nutrition.week }

    func choose(_ course: Meal.Course, number: Int, weekday: Int, plan: PersonalPlan) {
        update(plan, weekday) { $0.set(course, number) }
    }

    func toggleSnack(_ number: Int, weekday: Int, plan: PersonalPlan) {
        update(plan, weekday) { day in
            if let index = day.snacks.firstIndex(of: number) { day.snacks.remove(at: index) } else { day.snacks.append(number) }
        }
    }

    func resetWeek(for plan: PersonalPlan) {
        weeks[plan.id] = nil
        save()
    }

    // MARK: Grocery list

    func toggleChecked(_ lineID: String) {
        if checked.contains(lineID) { checked.remove(lineID) } else { checked.insert(lineID) }
        save()
    }

    func clearChecked() {
        checked = []
        save()
    }

    private func update(_ plan: PersonalPlan, _ weekday: Int, _ change: (inout DayMenu) -> Void) {
        var week = week(for: plan)
        guard let index = week.firstIndex(where: { $0.weekday == weekday }) else { return }
        change(&week[index])
        weeks[plan.id] = week
        save()
    }

    // MARK: Account backup

    /// Everything this store keeps, for syncing to the account.
    func exportData() -> Data {
        (try? JSONEncoder().encode(Snapshot(weeks: weeks, groceryPlanIDs: groceryPlanIDs, groceryDays: groceryDays, checked: checked))) ?? Data()
    }

    /// Replaces local data with a backup from the account.
    func restore(from data: Data) {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        weeks = snapshot.weeks
        groceryPlanIDs = snapshot.groceryPlanIDs
        groceryDays = snapshot.groceryDays ?? Set(1...7)
        checked = snapshot.checked
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(weeks: weeks, groceryPlanIDs: groceryPlanIDs, groceryDays: groceryDays, checked: checked)
        try? JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
