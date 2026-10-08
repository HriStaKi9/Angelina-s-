import Foundation

/// A person's coach-written plan: an eating plan plus the training program built around it.
/// Loaded from `Resources/Plans/<id>.json`; all prose is bilingual (see `Localized`).
struct PersonalPlan: Codable, Identifiable, Hashable {
    let id: String
    let name: Localized
    /// Theme color key: "berry" or "apricot".
    let accent: String
    let nutrition: NutritionPlan
    let training: TrainingProgram
    /// What the weekly check-in asks for.
    let checkIn: CheckInSpec
    /// Which plan section's adjustment table drives automatic advice: "nutrition" or "training".
    let adviceSource: String

    var adviceTable: AdjustmentTable? {
        adviceSource == "training" ? training.adjustments : nutrition.adjustments
    }
}

// MARK: - Bilingual text

enum ContentLanguage: String, Codable, CaseIterable, Identifiable {
    case bg, en

    var id: String { rawValue }
    var title: String { self == .bg ? "Български" : "English" }
    var shortTitle: String { rawValue.uppercased() }
}

struct Localized: Codable, Hashable {
    let bg: String
    let en: String

    subscript(language: ContentLanguage) -> String {
        switch language {
        case .bg: bg
        case .en: en
        }
    }
}

/// A value or an approximate range, written in JSON as `600` or `[650, 700]`.
struct ApproxRange: Codable, Hashable {
    let lower: Int
    let upper: Int

    init(_ lower: Int, _ upper: Int) {
        self.lower = lower
        self.upper = upper
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(Int.self) {
            self.init(single, single)
        } else {
            let pair = try container.decode([Int].self)
            guard pair.count == 2 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected [lower, upper]")
            }
            self.init(pair[0], pair[1])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if lower == upper { try container.encode(lower) } else { try container.encode([lower, upper]) }
    }

    var text: String { lower == upper ? "\(lower)" : "\(lower)–\(upper)" }

    static func + (lhs: ApproxRange, rhs: ApproxRange) -> ApproxRange {
        ApproxRange(lhs.lower + rhs.lower, lhs.upper + rhs.upper)
    }

    static let zero = ApproxRange(0, 0)
}

/// A titled block of guidance. `style` picks how it renders: plain list, warning or info callout.
struct InfoSection: Codable, Hashable, Identifiable {
    enum Style: String, Codable { case list, warning, info }

    let title: Localized
    let items: [Localized]
    var style: Style = .list

    var id: String { title.en }

    private enum CodingKeys: String, CodingKey { case title, items, style }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(Localized.self, forKey: .title)
        items = try c.decode([Localized].self, forKey: .items)
        style = try c.decodeIfPresent(Style.self, forKey: .style) ?? .list
    }
}

/// "If you see X → do Y" table used by both plans to adjust after 2–3 weeks.
struct AdjustmentTable: Codable, Hashable {
    struct Row: Codable, Hashable {
        let when: Localized
        let action: Localized
        /// Machine-readable version of `when`, so the app can match check-in data to this row.
        let trigger: AdviceTrigger?
    }

    let title: Localized
    let rows: [Row]
}

// MARK: - Nutrition

struct NutritionPlan: Codable, Hashable {
    let title: Localized
    let goal: Localized
    let stats: Localized
    let kcal: ApproxRange
    let protein: ApproxRange
    let mealsPerDay: Localized
    let pace: Localized
    let aboutTitle: Localized
    let about: [Localized]
    let meals: [Meal]
    let week: [DayMenu]
    let weekNote: Localized?
    let dayFlow: [Localized]?
    let sections: [InfoSection]
    let adjustments: AdjustmentTable?
    let important: Localized?

    func meals(for course: Meal.Course) -> [Meal] {
        meals.filter { $0.course == course }.sorted { $0.number < $1.number }
    }

    func meal(_ course: Meal.Course, _ number: Int) -> Meal? {
        meals.first { $0.course == course && $0.number == number }
    }

    /// Menu for a weekday, where 1 = Monday … 7 = Sunday.
    func menu(weekday: Int) -> DayMenu? {
        week.first { $0.weekday == weekday }
    }
}

struct Meal: Codable, Hashable, Identifiable {
    enum Course: String, Codable, CaseIterable, Identifiable {
        case breakfast, lunch, dinner, snack

        var id: String { rawValue }

        var title: Localized {
            switch self {
            case .breakfast: Localized(bg: "Закуска", en: "Breakfast")
            case .lunch: Localized(bg: "Обяд", en: "Lunch")
            case .dinner: Localized(bg: "Вечеря", en: "Dinner")
            case .snack: Localized(bg: "Междинно", en: "Snack")
            }
        }

        var pluralTitle: Localized {
            switch self {
            case .snack: Localized(bg: "Междинни", en: "Snacks")
            default: title
            }
        }

        var systemImage: String {
            switch self {
            case .breakfast: "sunrise.fill"
            case .lunch: "sun.max.fill"
            case .dinner: "moon.stars.fill"
            case .snack: "carrot.fill"
            }
        }
    }

    let course: Course
    let number: Int
    let name: Localized
    let ingredients: [Localized]
    let steps: Localized?
    let kcal: ApproxRange
    let protein: ApproxRange

    var id: String { "\(course.rawValue)-\(number)" }
}

struct DayMenu: Codable, Hashable {
    let weekday: Int
    let breakfast: Int
    let lunch: Int
    let dinner: Int
    let snacks: [Int]

    /// Meals in eating order: breakfast → snack → lunch → snack → dinner (→ extra snacks).
    func meals(in plan: NutritionPlan) -> [Meal] {
        let snackMeals = snacks.compactMap { plan.meal(.snack, $0) }
        var ordered: [Meal?] = [plan.meal(.breakfast, breakfast)]
        ordered.append(snackMeals.first)
        ordered.append(plan.meal(.lunch, lunch))
        ordered.append(snackMeals.dropFirst().first)
        ordered.append(plan.meal(.dinner, dinner))
        ordered += snackMeals.dropFirst(2).map(Optional.some)
        return ordered.compactMap { $0 }
    }

    func totals(in plan: NutritionPlan) -> (kcal: ApproxRange, protein: ApproxRange) {
        meals(in: plan).reduce((ApproxRange.zero, ApproxRange.zero)) { ($0.0 + $1.kcal, $0.1 + $1.protein) }
    }
}

// MARK: - Training

struct TrainingProgram: Codable, Hashable {
    let title: Localized
    let subtitle: Localized
    let stats: Localized
    /// One array of 7 days (Mon…Sun) per week in the rotation.
    let schedule: [[ScheduleDay]]
    let scheduleNote: Localized?
    let warmUp: [Localized]
    let callouts: [InfoSection]
    let workouts: [ProgramWorkout]
    let sections: [InfoSection]
    let adjustments: AdjustmentTable?
    /// Cut-down session for bad nights (first N exercises × M sets).
    let shortVersion: ShortVersion?
    /// Deload every N–M weeks.
    let deloadEvery: [Int]?

    struct ShortVersion: Codable, Hashable {
        let exercises: Int
        let sets: Int
        let note: Localized
    }

    func workout(id: String) -> ProgramWorkout? {
        workouts.first { $0.id == id }
    }

    /// The scheduled day for a date, given when the program was started.
    func day(on date: Date, startedOn start: Date, calendar: Calendar = .current) -> (week: Int, day: ScheduleDay)? {
        guard !schedule.isEmpty else { return nil }
        let week = Self.weekIndex(of: date, startedOn: start, calendar: calendar)
        let rotation = schedule[week % schedule.count]
        let weekday = Self.mondayBasedWeekday(of: date, calendar: calendar)
        guard rotation.indices.contains(weekday - 1) else { return nil }
        return (week + 1, rotation[weekday - 1])
    }

    static func weekIndex(of date: Date, startedOn start: Date, calendar: Calendar = .current) -> Int {
        let startMonday = mondayOfWeek(containing: start, calendar: calendar)
        let days = calendar.dateComponents([.day], from: startMonday, to: calendar.startOfDay(for: date)).day ?? 0
        return max(0, days / 7)
    }

    static func mondayBasedWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        // Calendar weekday: 1 = Sunday … 7 = Saturday → 1 = Monday … 7 = Sunday.
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    static func mondayOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(mondayBasedWeekday(of: date, calendar: calendar) - 1), to: start) ?? start
    }
}

struct ScheduleDay: Codable, Hashable {
    enum Kind: String, Codable { case workout, walk, steps, rest }

    let kind: Kind
    /// Set when `kind == .workout`.
    let workout: String?

    var systemImage: String {
        switch kind {
        case .workout: "dumbbell.fill"
        case .walk: "figure.walk"
        case .steps: "shoeprints.fill"
        case .rest: "bed.double.fill"
        }
    }

    var kindTitle: Localized {
        switch kind {
        case .workout: Localized(bg: "Тренировка", en: "Workout")
        case .walk: Localized(bg: "Разходка", en: "Walk")
        case .steps: Localized(bg: "Крачки", en: "Steps")
        case .rest: Localized(bg: "Почивка", en: "Rest")
        }
    }
}

struct ProgramWorkout: Codable, Hashable, Identifiable {
    let id: String
    /// Short label for the schedule strip, e.g. "A" or "Д1".
    let short: Localized
    let title: Localized
    let duration: Localized
    let focus: Localized?
    let exercises: [ProgramExercise]
    let finisher: Localized?
}

struct ProgramExercise: Codable, Hashable, Identifiable {
    /// Position in the workout: "1", "5a", "5b" (a/b = superset).
    let label: String
    let name: Localized
    let prescription: Localized
    let rest: Localized
    let start: Localized?
    let cues: [Localized]
    /// Matching entry in the exercise database, for photos and full instructions.
    let exerciseID: String?
    let tracking: ExerciseTracking
    /// Swappable options (suggested by the app, not part of the coach's plan).
    let alternatives: [ExerciseAlternative]

    var id: String { label }

    /// Option 0 is the plan's own exercise; 1… are alternatives.
    var options: [ExerciseOption] {
        [ExerciseOption(index: 0, name: name, exerciseID: exerciseID, place: nil, note: nil)]
            + alternatives.enumerated().map { ExerciseOption(index: $0.offset + 1, name: $0.element.name, exerciseID: $0.element.exerciseID, place: $0.element.place, note: $0.element.note) }
    }

    func option(_ index: Int) -> ExerciseOption {
        options.indices.contains(index) ? options[index] : options[0]
    }

    var isSuperset: Bool { label.last?.isLetter == true }
}

struct ExerciseAlternative: Codable, Hashable {
    let name: Localized
    let exerciseID: String?
    let place: Place
    let note: Localized?

    enum Place: String, Codable {
        case home, gym, any

        var title: Localized {
            switch self {
            case .home: Localized(bg: "У дома", en: "Home")
            case .gym: Localized(bg: "Фитнес", en: "Gym")
            case .any: Localized(bg: "Навсякъде", en: "Anywhere")
            }
        }
    }
}

struct ExerciseOption: Hashable, Identifiable {
    let index: Int
    let name: Localized
    let exerciseID: String?
    let place: ExerciseAlternative.Place?
    let note: Localized?

    var id: Int { index }
    var isOriginal: Bool { index == 0 }
    var exercise: Exercise? { exerciseID.flatMap(ExerciseLibrary.shared.exercise(id:)) }
}

/// How an exercise is logged and progressed, taken from the program's rules.
struct ExerciseTracking: Codable, Hashable {
    enum Load: String, Codable {
        /// `dumbbell` = one held weight (goblet); `dumbbells` = a pair, weight is per hand.
        case barbell, dumbbell, dumbbells, cable, band, bodyweight, assisted

        var usesWeight: Bool { [.barbell, .dumbbell, .dumbbells, .cable].contains(self) }
    }

    struct SetRule: Codable, Hashable {
        let from: Int
        let to: Int?
        let sets: Int
    }

    let sets: Int
    let reps: [Int]?
    let seconds: [Int]?
    let perSide: Bool
    let load: Load
    let start: [Double]?
    let step: Double?
    /// Weeks 1…N are done without added weight.
    let bodyweightWeeks: Int?
    /// Start without weight and add the starting weight once the top of the range is reached.
    let bodyweightFirst: Bool?
    let maxSeconds: Int?
    let setRules: [SetRule]?
    let restSeconds: Int

    var repRange: ClosedRange<Int>? { reps.map { $0[0]...$0[1] } }
    var secondRange: ClosedRange<Int>? { seconds.map { $0[0]...$0[1] } }
    var isTimed: Bool { seconds != nil }

    func sets(inWeek week: Int) -> Int {
        setRules?.first { week >= $0.from && week <= ($0.to ?? .max) }?.sets ?? sets
    }
}

// MARK: - Check-ins and advice

struct CheckInSpec: Codable, Hashable {
    let fields: [CheckInField]
    let flags: [CheckInFlag]
}

enum CheckInField: String, Codable, CaseIterable, Identifiable {
    case weight, waist, hips, steps

    var id: String { rawValue }

    var title: Localized {
        switch self {
        case .weight: Localized(bg: "Тегло", en: "Weight")
        case .waist: Localized(bg: "Талия", en: "Waist")
        case .hips: Localized(bg: "Ханш", en: "Hips")
        case .steps: Localized(bg: "Крачки (средно)", en: "Steps (daily avg)")
        }
    }

    var unit: Localized {
        switch self {
        case .weight: Localized(bg: "кг", en: "kg")
        case .waist, .hips: Localized(bg: "см", en: "cm")
        case .steps: Localized(bg: "крачки", en: "steps")
        }
    }
}

enum CheckInFlag: String, Codable, CaseIterable, Identifiable {
    case lowMilk, fatigue, hunger, poorSleep, jointPain

    var id: String { rawValue }

    var title: Localized {
        switch self {
        case .lowMilk: Localized(bg: "По-малко кърма", en: "Less breast milk")
        case .fatigue: Localized(bg: "Силна умора", en: "Heavy fatigue")
        case .hunger: Localized(bg: "Силен глад", en: "Strong hunger")
        case .poorSleep: Localized(bg: "Лош сън", en: "Poor sleep")
        case .jointPain: Localized(bg: "Болки в ставите", en: "Joint pain")
        }
    }
}

struct AdviceTrigger: Codable, Hashable {
    enum Kind: String, Codable { case steady, onTrack, losing, gaining, stalled, flags }

    let type: Kind
    let perWeek: Double?
    let afterWeek: Int?
    let weeks: Int?
    let withWaist: Bool?
    let anyOf: [CheckInFlag]?
    let maxGainPerWeek: Double?
    let maxLossPerWeek: Double?
    let minLossPerWeek: Double?
}
