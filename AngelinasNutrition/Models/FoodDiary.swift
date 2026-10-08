import Foundation

struct Nutrients: Codable, Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double?
    var fat: Double?

    static let zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
                  carbs: (lhs.carbs ?? 0) + (rhs.carbs ?? 0), fat: (lhs.fat ?? 0) + (rhs.fat ?? 0))
    }

    static func * (lhs: Nutrients, factor: Double) -> Nutrients {
        Nutrients(kcal: lhs.kcal * factor, protein: lhs.protein * factor,
                  carbs: lhs.carbs.map { $0 * factor }, fat: lhs.fat.map { $0 * factor })
    }
}

/// A food with nutrition per 100 g (or 100 ml): built-in basics or an Open Food Facts product.
struct FoodItem: Codable, Hashable, Identifiable {
    /// "basic:<key>" or "off:<barcode>".
    let id: String
    let name: Localized
    var brand: String?
    let per100: Nutrients
    /// Typical portion in grams (one egg, one slice, one serving); nil = 100 g.
    var portion: Double?

    func nutrients(grams: Double) -> Nutrients { per100 * (grams / 100) }
}

struct DiaryEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Local calendar day, "yyyy-MM-dd".
    let day: String
    let course: Meal.Course
    let name: Localized
    let detail: String?
    let nutrients: Nutrients
    /// Set when logged from a food (for recents and re-logging).
    var food: FoodItem?
    var grams: Double?
    /// Set when logged from the plan, e.g. "lunch-4".
    var planMealID: String?
}

struct CalorieGoal: Codable, Hashable {
    var kcal: Int
    var protein: Int?
    var carbs: Int?
    var fat: Int?
}

struct BodyStats: Codable, Hashable {
    enum Sex: String, Codable, CaseIterable, Identifiable {
        case female, male
        var id: String { rawValue }
    }

    var sex: Sex
    var weight: Double
    var height: Double
    var age: Int
    /// Activity multiplier on top of BMR (1.2 sedentary … 1.725 very active).
    var activity: Double
    /// Target change in kg per week (negative = lose).
    var weeklyChange: Double
    var breastfeeding: Bool
}

/// Mifflin-St Jeor, the formula both coach plans use.
enum CalorieCalculator {
    struct Result: Equatable {
        let bmr: Double
        let maintenance: Double
        let target: Double
        let protein: Int
        let fat: Int
        let carbs: Int
        /// True when the target was raised to the breastfeeding minimum.
        let hitFloor: Bool
    }

    static let activityLevels: [(value: Double, title: Localized)] = [
        (1.2, Localized(bg: "Заседнал (малко движение)", en: "Sedentary (little movement)")),
        (1.375, Localized(bg: "Леко активен (1–3 тренировки)", en: "Lightly active (1–3 workouts)")),
        (1.45, Localized(bg: "Активен с бебе (крачки + 3 тренировки)", en: "Active with a baby (steps + 3 workouts)")),
        (1.55, Localized(bg: "Умерено активен (3–5 тренировки)", en: "Moderately active (3–5 workouts)")),
        (1.725, Localized(bg: "Много активен (6–7 тренировки)", en: "Very active (6–7 workouts)")),
    ]

    /// ~7700 kcal per kg of body weight.
    static let kcalPerKg = 7700.0
    /// Extra energy for breastfeeding (the plan uses ≈ 350–450 kcal at 6 months).
    static let breastfeedingExtra = 400.0
    /// The plan's floor while breastfeeding.
    static let breastfeedingFloor = 1800.0

    static func calculate(_ body: BodyStats, proteinPerKg: Double = 2.0) -> Result {
        let base = 10 * body.weight + 6.25 * body.height - 5 * Double(body.age)
        let bmr = base + (body.sex == .male ? 5 : -161)
        var maintenance = bmr * body.activity
        if body.breastfeeding { maintenance += breastfeedingExtra }
        var target = maintenance + body.weeklyChange * kcalPerKg / 7
        let floor = body.breastfeeding ? breastfeedingFloor : (body.sex == .male ? 1500 : 1200)
        let hitFloor = target < floor
        target = max(target, floor)
        let protein = Int((body.weight * proteinPerKg).rounded())
        let fat = Int((target * 0.30 / 9).rounded())
        let carbs = max(0, Int(((target - Double(protein) * 4 - Double(fat) * 9) / 4).rounded()))
        return Result(bmr: bmr, maintenance: maintenance, target: target, protein: protein, fat: fat, carbs: carbs, hitFloor: hitFloor)
    }
}
