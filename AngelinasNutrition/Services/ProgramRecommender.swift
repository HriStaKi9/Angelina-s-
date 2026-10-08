import Foundation

/// Builds a full training program for a goal, from the exercise database, filtered by the user's
/// equipment and level: the same shape as the coach programs, so logging and progression just work.
enum ProgramRecommender {
    struct Input: Equatable {
        var goal: FitnessGoal
        var sessionsPerWeek: Int
        var gear: Set<HomeGear>
        var level: Exercise.Level
        var avoid: Set<Exercise.Category> = []
    }

    /// Movement patterns; each lists exercise ids from most to least preferred (gym → home).
    enum Slot: String, CaseIterable {
        case squat, hinge, glute, lunge, hPush, incline, vPush, vPull, hPull, core, biceps, triceps, abduction, rearDelt, calves

        var candidates: [String] {
            switch self {
            case .squat: ["Barbell_Squat", "Goblet_Squat", "Leg_Press", "Dumbbell_Squat", "Bodyweight_Squat"]
            case .hinge: ["Romanian_Deadlift", "Stiff-Legged_Dumbbell_Deadlift", "Barbell_Deadlift", "Kettlebell_One-Legged_Deadlift", "Good_Morning"]
            case .glute: ["Barbell_Hip_Thrust", "Barbell_Glute_Bridge", "Single_Leg_Glute_Bridge", "Butt_Lift_Bridge"]
            case .lunge: ["Split_Squat_with_Dumbbells", "Dumbbell_Rear_Lunge", "Dumbbell_Lunges", "Barbell_Lunge", "Bodyweight_Walking_Lunge"]
            case .hPush: ["Barbell_Bench_Press_-_Medium_Grip", "Dumbbell_Bench_Press", "Pushups"]
            case .incline: ["Incline_Dumbbell_Press", "Barbell_Incline_Bench_Press_-_Medium_Grip", "Incline_Push-Up"]
            case .vPush: ["Standing_Military_Press", "Seated_Dumbbell_Press", "Dumbbell_Shoulder_Press", "Shoulder_Press_-_With_Bands"]
            case .vPull: ["Pullups", "Wide-Grip_Lat_Pulldown", "Band_Assisted_Pull-Up", "Chin-Up"]
            case .hPull: ["Bent_Over_Barbell_Row", "Seated_Cable_Rows", "One-Arm_Dumbbell_Row", "Bent_Over_Two-Dumbbell_Row", "Inverted_Row"]
            case .core: ["Dead_Bug", "Plank", "Pallof_Press", "Side_Bridge", "Reverse_Crunch"]
            case .biceps: ["Dumbbell_Bicep_Curl", "Barbell_Curl", "Hammer_Curls"]
            case .triceps: ["Close-Grip_Barbell_Bench_Press", "Triceps_Pushdown", "Standing_Dumbbell_Triceps_Extension", "Tricep_Dumbbell_Kickback", "Bench_Dips"]
            case .abduction: ["Monster_Walk", "One-Legged_Cable_Kickback", "Glute_Kickback"]
            case .rearDelt: ["Face_Pull", "Reverse_Flyes", "Band_Pull_Apart"]
            case .calves: ["Standing_Calf_Raises", "Standing_Dumbbell_Calf_Raise", "Calf_Raise_On_A_Dumbbell"]
            }
        }

        /// Big multi-joint lifts get the heavier set/rep scheme.
        var isMain: Bool { [.squat, .hinge, .glute, .hPush, .vPush, .vPull, .hPull].contains(self) }
    }

    struct DayTemplate {
        let id: String
        let short: Localized
        let title: Localized
        let focus: Localized
        let slots: [Slot]
    }

    // MARK: Program

    static func program(for input: Input, library: ExerciseLibrary = .shared) -> TrainingProgram {
        let days = templates(for: input)
        let workouts = days.map { day in
            ProgramWorkout(
                id: day.id, short: day.short, title: day.title,
                duration: Localized(bg: "~\(duration(day, input)) мин", en: "~\(duration(day, input)) min"),
                focus: day.focus,
                exercises: exercises(for: day, input: input, library: library),
                finisher: finisher(input.goal))
        }
        return TrainingProgram(
            title: title(input), subtitle: subtitle(input),
            stats: Localized(bg: "\(input.sessionsPerWeek) тренировки седмично · \(input.goal.titleBG.lowercased())",
                             en: "\(input.sessionsPerWeek) workouts a week · \(input.goal.title.lowercased())"),
            schedule: schedule(workoutIDs: workouts.map(\.id), sessions: input.sessionsPerWeek, goal: input.goal),
            scheduleNote: scheduleNote(input.goal),
            warmUp: [
                Localized(bg: "5 мин бързо ходене или колело", en: "5 min brisk walk or bike"),
                Localized(bg: "Клякания без тежест 2×10 и разтягане на ластик 2×15", en: "Bodyweight squats 2×10 and band pull-aparts 2×15"),
                Localized(bg: "1–2 леки серии на първото упражнение", en: "1–2 light sets of the first exercise"),
            ],
            callouts: [InfoSection(title: Localized(bg: "Как е съставена", en: "How it was built"),
                                   items: [Localized(bg: "Автоматично от целта, оборудването и нивото ти. Не е от треньор – слушай тялото си и при болка спри.",
                                                     en: "Generated from your goal, equipment and level. It isn't from a coach – listen to your body and stop if something hurts.")],
                                   style: .info)],
            workouts: workouts,
            sections: [
                InfoSection(title: Localized(bg: "Как се покачват тежестите", en: "How to progress"), items: [
                    Localized(bg: "Седмица 1: намери тежест, при която последната серия е с 2–3 повторения в запас.",
                              en: "Week 1: find a weight where the last set has 2–3 reps in reserve."),
                    Localized(bg: "Двойна прогресия: стигнеш ли горната граница на повторенията във всички серии, добави тежест и започни от долната.",
                              en: "Double progression: once you hit the top of the rep range on every set, add weight and restart at the bottom."),
                    Localized(bg: "Разтоварване на всеки 6–8 седмици: същите тежести, половината серии.",
                              en: "Deload every 6–8 weeks: same weights, half the sets."),
                ]),
                InfoSection(title: Localized(bg: "Храненето и целта", en: "Food and the goal"), items: [goalFoodNote(input.goal)]),
            ],
            adjustments: nil, shortVersion: nil, deloadEvery: [6, 8],
            extraExercises: input.avoid.isEmpty ? nil : TrainingProgram.ExtraExercises(
                avoidCategories: Array(input.avoid), note: Localized(bg: "Без скокове.", en: "No jumping.")))
    }

    static func templates(for input: Input) -> [DayTemplate] {
        let tone = input.goal == .tone
        let fatLoss = input.goal == .loseFat
        func day(_ id: String, _ shortBG: String, _ shortEN: String, _ bg: String, _ en: String, _ fbg: String, _ fen: String, _ slots: [Slot]) -> DayTemplate {
            DayTemplate(id: "rec-\(id)", short: Localized(bg: shortBG, en: shortEN), title: Localized(bg: bg, en: en),
                        focus: Localized(bg: fbg, en: fen), slots: slots)
        }
        let fullA = day("A", "A", "A", "Цяло тяло A", "Full body A", "клек, гърди, гръб, корем", "squat, chest, back, core",
                        tone ? [.squat, .glute, .hPush, .hPull, .abduction, .core] : [.squat, .hPush, .hPull, .hinge, .core])
        let fullB = day("B", "B", "B", "Цяло тяло B", "Full body B", "задно бедро, рамене, набиране, корем", "hinge, shoulders, pull, core",
                        tone ? [.hinge, .lunge, .vPush, .vPull, .glute, .core] : [.hinge, .lunge, .vPush, .vPull, .core])
        let lowerA = day("LA", "Д1", "L1", "Долна част A", "Lower A", "клек и седалище", "squat and glutes",
                         tone || fatLoss ? [.squat, .glute, .lunge, .abduction, .core] : [.squat, .hinge, .lunge, .calves, .core])
        let upperA = day("UA", "Г1", "U1", "Горна част A", "Upper A", "лежанка и гребане", "press and row",
                         [.hPush, .hPull, .vPush, .vPull, .triceps, .biceps])
        let lowerB = day("LB", "Д2", "L2", "Долна част B", "Lower B", "задно бедро и седалище", "hinge and glutes",
                         tone || fatLoss ? [.hinge, .glute, .lunge, .abduction, .core] : [.hinge, .squat, .glute, .calves, .core])
        let upperB = day("UB", "Г2", "U2", "Горна част B", "Upper B", "рамене и набиране", "shoulders and pull",
                         [.vPush, .vPull, .incline, .hPull, .rearDelt, .core])
        let push = day("P", "Бу", "Pu", "Бутане", "Push", "гърди, рамене, трицепс", "chest, shoulders, triceps",
                       [.hPush, .vPush, .incline, .triceps, .core])
        let pull = day("PL", "Др", "Pl", "Дърпане", "Pull", "гръб и бицепс", "back and biceps",
                       [.vPull, .hPull, .rearDelt, .biceps, .core])
        let legs = day("LG", "Кр", "Lg", "Крака", "Legs", "крака и седалище", "legs and glutes",
                       [.squat, .hinge, .lunge, .glute, .calves])

        switch input.sessionsPerWeek {
        case ...3: return [fullA, fullB]
        case 4: return [lowerA, upperA, lowerB, upperB]
        default:
            // Build muscle gets push/pull/legs; the other goals keep upper/lower with more glute and conditioning work.
            return input.goal == .buildMuscle ? [push, pull, legs, upperA, lowerA] : [lowerA, upperA, lowerB, upperB]
        }
    }

    // MARK: Exercises

    static func exercises(for day: DayTemplate, input: Input, library: ExerciseLibrary) -> [ProgramExercise] {
        var used: Set<String> = []
        var result: [ProgramExercise] = []
        // With little equipment some slots have no option; bodyweight moves top the day up to 4 exercises.
        let fallback: [(String, Slot)] = [("Pushups", .hPush), ("Push-Ups_-_Close_Triceps_Position", .triceps),
                                          ("Bodyweight_Squat", .squat), ("Bodyweight_Walking_Lunge", .lunge),
                                          ("Butt_Lift_Bridge", .glute), ("Glute_Kickback", .abduction),
                                          ("Step-up_with_Knee_Raise", .lunge), ("Plank", .core), ("Side_Bridge", .core),
                                          ("Reverse_Crunch", .core)]
        let planned = day.slots.map { ($0, $0.candidates) }
        let topUp = fallback.map { ($0.1, [$0.0]) }
        for (index, (slot, candidates)) in (planned + topUp).enumerated() {
            if index >= planned.count && result.count >= 4 { break }
            let doable = candidates.compactMap(library.exercise(id:)).filter {
                $0.isDoable(with: input.gear) && !input.avoid.contains($0.category)
                    && ($0.level != .expert || input.level == .expert) && !used.contains($0.id)
            }
            guard let pick = doable.first else { continue }
            used.insert(pick.id)
            let label = "\(result.count + 1)"
            let tracking = tracking(for: pick, slot: slot, goal: input.goal)
            result.append(ProgramExercise(
                label: label,
                name: Localized(bg: pick.name, en: pick.name),
                prescription: prescription(tracking),
                rest: restText(tracking.restSeconds),
                start: nil,
                cues: pick.instructions.prefix(1).map { Localized(bg: $0, en: $0) },
                exerciseID: pick.id,
                tracking: tracking,
                alternatives: doable.dropFirst().prefix(2).map {
                    ExerciseAlternative(name: Localized(bg: $0.name, en: $0.name), exerciseID: $0.id,
                                        place: [.cable, .machine].contains($0.resolvedEquipment) ? .gym : .any, note: nil)
                }))
        }
        return result
    }

    static func tracking(for exercise: Exercise, slot: Slot, goal: FitnessGoal) -> ExerciseTracking {
        let name = exercise.name.lowercased()
        let perSide = ["one-arm", "one-legged", "single", "lunge", "split", "monster", "kickback", "side bridge"].contains { name.contains($0) }
        let load: ExerciseTracking.Load = {
            switch exercise.resolvedEquipment {
            case .barbell, .ezCurlBar: .barbell
            case .dumbbell: name.contains("goblet") || name.contains("one-arm") ? .dumbbell : .dumbbells
            case .kettlebells: .dumbbell
            case .cable, .machine: .cable
            case .bands: .band
            case .other: name.contains("assisted") ? .assisted : .bodyweight
            default: name.contains("pull") || name.contains("chin") ? .assisted : .bodyweight
            }
        }()
        let step: Double? = switch load {
        case .barbell: [.squat, .hinge, .glute].contains(slot) ? 5 : 2.5
        case .dumbbell, .dumbbells: 2
        case .cable: 2.5
        default: nil
        }
        // Holds are timed.
        if name == "plank" || name.contains("side bridge") {
            return ExerciseTracking(sets: 3, reps: nil, seconds: [30, 30], perSide: perSide, load: .bodyweight, start: nil,
                                    step: nil, bodyweightWeeks: nil, bodyweightFirst: nil, maxSeconds: 60, setRules: nil, restSeconds: 45)
        }
        let main = slot.isMain
        let (sets, reps, rest): (Int, [Int], Int) = switch goal {
        case .loseFat: (3, main ? [10, 12] : [12, 15], main ? 60 : 45)
        case .tone: (3, main ? [8, 12] : [12, 15], main ? 75 : 60)
        case .buildMuscle: main ? (4, [6, 10], 120) : (3, [10, 12], 75)
        case .maintain: (3, [10, 12], 60)
        }
        let pullUps = load == .assisted
        return ExerciseTracking(sets: sets, reps: pullUps ? [4, 8] : reps, seconds: nil, perSide: perSide, load: load,
                                start: nil, step: step, bodyweightWeeks: nil, bodyweightFirst: nil, maxSeconds: nil,
                                setRules: goal == .buildMuscle && main ? [.init(from: 1, to: 2, sets: 3)] : nil,
                                restSeconds: pullUps ? 90 : rest)
    }

    // MARK: Text

    static func prescription(_ t: ExerciseTracking) -> Localized {
        let amount: String
        if let s = t.seconds { amount = "\(t.sets) × \(s[0])" } else if let r = t.reps { amount = "\(t.sets) × \(r[0])–\(r[1])" } else { amount = "\(t.sets)" }
        let bg = amount + (t.seconds != nil ? " сек" : "") + (t.perSide ? " на страна" : "")
        let en = amount + (t.seconds != nil ? " s" : "") + (t.perSide ? " per side" : "")
        return Localized(bg: bg, en: en)
    }

    static func restText(_ seconds: Int) -> Localized {
        seconds >= 120 && seconds % 60 == 0
            ? Localized(bg: "\(seconds / 60) мин", en: "\(seconds / 60) min")
            : Localized(bg: "\(seconds) сек", en: "\(seconds) s")
    }

    static func duration(_ day: DayTemplate, _ input: Input) -> Int {
        let perExercise = input.goal == .buildMuscle ? 10 : 8
        return day.slots.count * perExercise + 10 + (input.goal == .loseFat ? 12 : 0)
    }

    static func finisher(_ goal: FitnessGoal) -> Localized? {
        switch goal {
        case .loseFat: Localized(bg: "Финал: 12 мин бързо ходене с наклон или колело.", en: "Finisher: 12 min brisk incline walk or bike.")
        case .maintain: Localized(bg: "Финал: 5 мин разтягане.", en: "Finisher: 5 min stretching.")
        default: nil
        }
    }

    static func schedule(workoutIDs: [String], sessions: Int, goal: FitnessGoal) -> [[ScheduleDay]] {
        let n = max(2, min(6, sessions))
        let trainingDays: [Int] = switch n {
        case 2: [0, 3]
        case 3: [0, 2, 4]
        case 4: [0, 1, 3, 4]
        case 5: [0, 1, 2, 3, 4]
        default: [0, 1, 2, 3, 4, 5]
        }
        let offDay = ScheduleDay(kind: goal == .loseFat ? .steps : .walk, workout: nil)
        // Two workouts over an odd number of days rotate week to week (A-B-A, then B-A-B).
        let weeks = workoutIDs.count == 2 && n % 2 == 1 ? 2 : 1
        return (0..<weeks).map { week in
            var counter = week * n
            return (0..<7).map { day in
                guard trainingDays.contains(day) else { return day == 6 ? ScheduleDay(kind: .rest, workout: nil) : offDay }
                defer { counter += 1 }
                return ScheduleDay(kind: .workout, workout: workoutIDs[counter % workoutIDs.count])
            }
        }
    }

    static func title(_ input: Input) -> Localized {
        switch input.goal {
        case .loseFat: Localized(bg: "Програма за отслабване", en: "Fat-loss program")
        case .tone: Localized(bg: "Програма за стягане", en: "Tone & sculpt program")
        case .buildMuscle: Localized(bg: "Програма за мускулна маса", en: "Muscle-building program")
        case .maintain: Localized(bg: "Програма за здраве и форма", en: "Health & fitness program")
        }
    }

    static func subtitle(_ input: Input) -> Localized {
        let split: Localized = switch input.sessionsPerWeek {
        case ...3: Localized(bg: "цяло тяло A/B", en: "full body A/B")
        case 4: Localized(bg: "горна/долна част", en: "upper/lower")
        default: input.goal == .buildMuscle ? Localized(bg: "бутане/дърпане/крака", en: "push/pull/legs") : Localized(bg: "горна/долна част", en: "upper/lower")
        }
        return Localized(bg: "Препоръчана · \(split.bg)", en: "Recommended · \(split.en)")
    }

    static func scheduleNote(_ goal: FitnessGoal) -> Localized {
        switch goal {
        case .loseFat: Localized(bg: "В дните без тренировка: 8 000–10 000 крачки.", en: "On non-training days: 8,000–10,000 steps.")
        default: Localized(bg: "Поне ден почивка преди същата тренировка отново.", en: "At least a day's rest before the same workout again.")
        }
    }

    static func goalFoodNote(_ goal: FitnessGoal) -> Localized {
        switch goal {
        case .loseFat: Localized(bg: "Лек калориен дефицит (≈ −0.5 кг седмично) и много протеин, за да се пази мускулът.", en: "A moderate calorie deficit (≈ −0.5 kg a week) with plenty of protein to keep muscle.")
        case .tone: Localized(bg: "Лек дефицит или поддръжка, протеин при всяко хранене.", en: "A slight deficit or maintenance, protein at every meal.")
        case .buildMuscle: Localized(bg: "Лек излишък (≈ +0.25 кг седмично) и ≈ 2 г протеин на кг.", en: "A small surplus (≈ +0.25 kg a week) and ≈ 2 g protein per kg.")
        case .maintain: Localized(bg: "Калории на поддръжка, разнообразно хранене.", en: "Maintenance calories and varied food.")
        }
    }
}

extension FitnessGoal {
    var titleBG: String {
        switch self {
        case .loseFat: "Отслабване"
        case .tone: "Стягане"
        case .buildMuscle: "Мускулна маса"
        case .maintain: "Здраве и форма"
        }
    }
}
