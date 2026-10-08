import Foundation

/// What to do next time for one exercise.
struct SetSuggestion: Equatable {
    let sets: Int
    /// Suggested load in kg (per hand for dumbbell pairs); nil = bodyweight / band / no number.
    let weight: Double?
    let reps: ClosedRange<Int>?
    let seconds: Int?
    let reason: Localized
}

/// Applies the training program's progression rules:
/// - Week 1: start at the low end of the starting weight.
/// - "More than 3 reps in reserve" on every set → add weight next time.
/// - Double progression: top of the rep range on every set → add weight, restart at the bottom.
/// - Increments: barbell +5 / +2.5 kg, dumbbells: next pair, cable: +1 step, band: stronger.
/// - Core holds: +5 s a week up to the cap.
enum ProgressionCoach {
    /// - Parameters:
    ///   - history: past performances of this exercise option, newest first.
    static func suggest(for tracking: ExerciseTracking,
                        week: Int,
                        history: [(week: Int, exercise: LoggedExercise)],
                        isDeload: Bool = false,
                        shortSets: Int? = nil) -> SetSuggestion {
        var sets = shortSets ?? tracking.sets(inWeek: week)
        if isDeload { sets = max(1, Int((Double(sets) / 2).rounded(.up))) }

        if let range = tracking.secondRange {
            return timed(tracking: tracking, range: range, sets: sets, week: week, last: history.first)
        }

        let reps = tracking.repRange
        let last = history.first?.exercise

        guard tracking.load.usesWeight else {
            return unweighted(tracking: tracking, reps: reps, sets: sets, last: last)
        }

        let startWeight = tracking.start?.first

        if let bodyweightWeeks = tracking.bodyweightWeeks, week <= bodyweightWeeks {
            return SetSuggestion(sets: sets, weight: nil, reps: reps, seconds: nil,
                                 reason: Localized(bg: "Седмици 1–\(bodyweightWeeks): без тежест – балансът е по-трудното.",
                                                   en: "Weeks 1–\(bodyweightWeeks): bodyweight – balance is the hard part."))
        }

        let lastWeight = last?.topWeight
        guard let last, lastWeight != nil || tracking.bodyweightFirst == true else {
            return SetSuggestion(sets: sets, weight: startWeight, reps: reps, seconds: nil,
                                 reason: Localized(bg: "Започни от долната граница на стартовата тежест.",
                                                   en: "Start at the low end of the starting weight."))
        }

        let hitTop = reachedTop(last, reps: reps, plannedSets: sets)

        // Bodyweight-first moves: earn the starting weight by maxing out the range without it.
        if lastWeight == nil {
            if hitTop || last.feltEasy {
                return SetSuggestion(sets: sets, weight: startWeight, reps: reps, seconds: nil,
                                     reason: Localized(bg: "Горната граница без тежест е достигната – добави дъмбели.",
                                                       en: "Top of the range without weight – add dumbbells."))
            }
            return SetSuggestion(sets: sets, weight: nil, reps: reps, seconds: nil,
                                 reason: Localized(bg: "Още без тежест, докато стигнеш горната граница.",
                                                   en: "Stay at bodyweight until you hit the top of the range."))
        }

        let current = lastWeight ?? startWeight ?? 0
        if last.feltEasy || hitTop {
            let next = current + (tracking.step ?? 0)
            let why = last.feltEasy && !hitTop
                ? Localized(bg: "Повече от 3 повторения в запас → добави тежест.", en: "More than 3 reps in reserve → add weight.")
                : Localized(bg: "Двойна прогресия: горната граница е достигната → \(incrementText(tracking).bg), започни от долната граница.",
                            en: "Double progression: top of the range reached → \(incrementText(tracking).en), restart at the bottom.")
            return SetSuggestion(sets: sets, weight: next, reps: reps, seconds: nil, reason: why)
        }

        let lastReps = last.lastDoneSet?.reps
        return SetSuggestion(sets: sets, weight: current, reps: reps, seconds: nil,
                             reason: lastReps.map {
                                 Localized(bg: "Същата тежест – опитай повече от \($0) повторения в последната серия.",
                                           en: "Same weight – beat \($0) reps on the last set.")
                             } ?? Localized(bg: "Същата тежест.", en: "Same weight."))
    }

    static func incrementText(_ tracking: ExerciseTracking) -> Localized {
        let step = tracking.step.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        switch tracking.load {
        case .barbell: return Localized(bg: "+\(step) кг", en: "+\(step) kg")
        case .dumbbell, .dumbbells: return Localized(bg: "следващата тежест (≈ +\(step) кг)", en: "next dumbbell (≈ +\(step) kg)")
        case .cable: return Localized(bg: "+1 стъпка", en: "+1 plate")
        case .band: return Localized(bg: "по-силен ластик", en: "a stronger band")
        case .assisted: return Localized(bg: "по-лек ластик", en: "a lighter band")
        case .bodyweight: return Localized(bg: "+1–2 повторения", en: "+1–2 reps")
        }
    }

    private static func reachedTop(_ exercise: LoggedExercise, reps: ClosedRange<Int>?, plannedSets: Int) -> Bool {
        guard let top = reps?.upperBound else { return false }
        let done = exercise.doneSets
        return done.count >= min(plannedSets, exercise.sets.count) && !done.isEmpty && done.allSatisfy { ($0.reps ?? 0) >= top }
    }

    private static func unweighted(tracking: ExerciseTracking, reps: ClosedRange<Int>?, sets: Int, last: LoggedExercise?) -> SetSuggestion {
        guard let last, reachedTop(last, reps: reps, plannedSets: sets) || last.feltEasy else {
            return SetSuggestion(sets: sets, weight: nil, reps: reps, seconds: nil,
                                 reason: Localized(bg: "Качеството е по-важно от повторенията.", en: "Quality matters more than reps."))
        }
        return SetSuggestion(sets: sets, weight: nil, reps: reps, seconds: nil,
                             reason: Localized(bg: "Горната граница е достигната → \(incrementText(tracking).bg).",
                                               en: "Top of the range reached → \(incrementText(tracking).en)."))
    }

    private static func timed(tracking: ExerciseTracking, range: ClosedRange<Int>, sets: Int, week: Int,
                              last: (week: Int, exercise: LoggedExercise)?) -> SetSuggestion {
        let cap = tracking.maxSeconds ?? range.upperBound
        guard let last, let held = last.exercise.doneSets.compactMap(\.seconds).min() else {
            return SetSuggestion(sets: sets, weight: nil, reps: nil, seconds: range.lowerBound,
                                 reason: Localized(bg: "Започни с \(range.lowerBound) сек.", en: "Start with \(range.lowerBound) s."))
        }
        if held >= cap {
            return SetSuggestion(sets: sets, weight: nil, reps: nil, seconds: cap,
                                 reason: cap == range.upperBound && tracking.maxSeconds == nil
                                    ? Localized(bg: "\(cap) сек са лесни → премини на по-труден вариант (на стъпала).",
                                                en: "\(cap) s is easy → move to the harder version (on the feet).")
                                    : Localized(bg: "Максимумът от \(cap) сек е достигнат.", en: "You've reached the \(cap) s cap."))
        }
        // The plan progresses holds weekly, so only step up once per program week.
        let next = last.week < week ? min(held + 5, cap) : held
        return SetSuggestion(sets: sets, weight: nil, reps: nil, seconds: next,
                             reason: next > held
                                ? Localized(bg: "+5 сек спрямо миналата седмица.", en: "+5 s on last week.")
                                : Localized(bg: "Задръж същото тази седмица.", en: "Hold the same this week."))
    }
}
