import Foundation

struct Workout: Equatable {
    let title: String
    let focus: [Exercise.MuscleGroup]
    let prescription: Prescription
    let warmUp: [Exercise]
    let main: [Exercise]

    var estimatedMinutes: Int {
        // ~40s per set plus rest, plus ~5 minutes of warm-up.
        let perSet = 40 + prescription.restSeconds
        return (main.count * prescription.sets * perSet) / 60 + 5
    }
}

/// Builds today's workout from the user's goal, location and equipment.
/// The result is deterministic for a given day, so the plan doesn't change on every launch.
struct WorkoutPlanner {
    let library: ExerciseLibrary

    func workout(for profile: UserProfile, on date: Date = .now, calendar: Calendar = .current) -> Workout {
        let split = Self.split(sessionsPerWeek: profile.sessionsPerWeek)
        let dayNumber = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let day = split[dayNumber % split.count]
        // hashValue is randomized per launch, so seed from the goal's stable position instead.
        let goalIndex = FitnessGoal.allCases.firstIndex(of: profile.goal) ?? 0
        var rng = SeededGenerator(seed: UInt64(dayNumber) &* 31 &+ UInt64(goalIndex))

        let pool = library.available(for: profile).filter { $0.level <= profile.level }
        let training = pool.filter { [.strength, .plyometrics, .cardio, .powerlifting].contains($0.category) }
        let stretches = pool.filter { $0.category == .stretching }

        var picked: [Exercise] = []
        func pick(from candidates: [Exercise], preferCompound: Bool) {
            let fresh = candidates.filter { !picked.contains($0) }
            let preferred = fresh.filter { $0.isCompound == preferCompound }
            if let choice = (preferred.isEmpty ? fresh : preferred).randomElement(using: &rng) {
                picked.append(choice)
            }
        }

        for slot in day.slots(for: profile.goal) {
            let candidates = training.filter { ex in
                ex.primaryMuscles.contains { slot.muscles.contains($0) }
                    && (slot.categories.isEmpty || slot.categories.contains(ex.category))
            }
            pick(from: candidates, preferCompound: slot.compound)
        }

        let focusMuscles = Set(picked.flatMap(\.primaryMuscles))
        var warmUp: [Exercise] = []
        for stretch in stretches.shuffled(using: &rng) where warmUp.count < 2 {
            if stretch.primaryMuscles.contains(where: focusMuscles.contains) { warmUp.append(stretch) }
        }

        return Workout(
            title: day.title,
            focus: day.focus,
            prescription: profile.goal.prescription,
            warmUp: warmUp,
            main: picked
        )
    }

    // MARK: - Splits

    struct Day {
        let title: String
        let focus: [Exercise.MuscleGroup]

        func slots(for goal: FitnessGoal) -> [Slot] {
            var slots: [Slot] = []
            for group in focus {
                switch group {
                case .legs:
                    slots += [Slot(muscles: [.quadriceps], compound: true),
                              Slot(muscles: [.glutes, .hamstrings], compound: true)]
                    if goal == .tone || goal == .loseFat {
                        slots.append(Slot(muscles: [.glutes, .abductors, .adductors], compound: false))
                    }
                case .push:
                    slots += [Slot(muscles: [.chest], compound: true),
                              Slot(muscles: [.shoulders], compound: focus.count == 1)]
                    if focus.count <= 2 { slots.append(Slot(muscles: [.triceps], compound: false)) }
                case .pull:
                    slots += [Slot(muscles: [.lats, .middleBack], compound: true)]
                    if focus.count <= 2 { slots.append(Slot(muscles: [.biceps], compound: false)) }
                case .core:
                    slots.append(Slot(muscles: [.abdominals], compound: false))
                }
            }
            if goal == .loseFat {
                slots.append(Slot(muscles: Exercise.Muscle.allCases, compound: true, categories: [.plyometrics, .cardio]))
            }
            return slots
        }
    }

    struct Slot {
        let muscles: [Exercise.Muscle]
        let compound: Bool
        var categories: [Exercise.Category] = []
    }

    static func split(sessionsPerWeek: Int) -> [Day] {
        switch sessionsPerWeek {
        case ...3:
            return [Day(title: "Full Body", focus: [.legs, .push, .pull, .core])]
        case 4:
            return [Day(title: "Lower Body", focus: [.legs, .core]),
                    Day(title: "Upper Body", focus: [.push, .pull])]
        default:
            return [Day(title: "Legs & Glutes", focus: [.legs]),
                    Day(title: "Push", focus: [.push, .core]),
                    Day(title: "Pull", focus: [.pull, .core])]
        }
    }
}

/// Small deterministic RNG (SplitMix64) so a day's plan is stable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
