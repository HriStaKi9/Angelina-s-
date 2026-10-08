import Foundation
import Observation

/// Holds the user's profile and persists it to UserDefaults on every change.
@Observable
final class ProfileStore {
    private static let key = "userProfile.v1"
    private let defaults: UserDefaults

    var profile: UserProfile {
        didSet { save() }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = stored
        } else {
            profile = UserProfile()
        }
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    // MARK: Personal plans

    var activePlan: PersonalPlan? { PlanLibrary.shared.plan(id: profile.planID) }

    /// The plan whose training program is in use: the coach's, or a started recommended program
    /// (wrapped as a plan so workouts, logging and progression work the same way).
    var trainingPlan: PersonalPlan? {
        guard let plan = baseTrainingPlan else { return nil }
        guard let everyWeek = profile.scheduleEdits?[scheduleKey(plan)]?.everyWeek else { return plan }
        return plan.with(training: plan.training.with(schedule: everyWeek))
    }

    /// Training plan before the user's schedule edits.
    private var baseTrainingPlan: PersonalPlan? {
        guard let recommended = profile.recommendedProgram else { return activePlan }
        let base = activePlan
        return PersonalPlan(
            id: base?.id ?? "personal",
            name: base?.name ?? Localized(bg: profile.firstName.isEmpty ? "Аз" : profile.firstName,
                                          en: profile.firstName.isEmpty ? "Me" : profile.firstName),
            accent: base?.accent ?? "berry",
            nutrition: base?.nutrition ?? .empty,
            training: recommended.program,
            checkIn: base?.checkIn ?? CheckInSpec(fields: [.weight, .waist], flags: [.fatigue]),
            adviceSource: base?.adviceSource ?? "nutrition",
            body: base?.body,
            steps: base?.steps)
    }

    func startRecommended(_ recommended: RecommendedProgram) {
        profile.recommendedProgram = recommended
        profile.programStart = TrainingProgram.mondayOfWeek(containing: .now)
    }

    func stopRecommended() {
        profile.recommendedProgram = nil
        profile.programStart = profile.planID == nil ? nil : TrainingProgram.mondayOfWeek(containing: .now)
    }

    /// Language for plan content. Plans are written in Bulgarian, so that's the default.
    var language: ContentLanguage {
        get { profile.language ?? .bg }
        set { profile.language = newValue }
    }

    var gear: Set<HomeGear> {
        get { profile.gear ?? HomeGear.defaultSet }
        set { profile.gear = newValue }
    }

    /// The look in use: the chosen one, or automatically Steel when the active plan is a man's.
    var theme: ThemeVariant {
        profile.theme ?? (activePlan?.body?.sex == .male ? .steel : .rose)
    }

    /// Picks interface copy for plan screens in the current content language.
    func t(_ bg: String, _ en: String) -> String { language == .bg ? bg : en }

    var programStart: Date {
        profile.programStart ?? TrainingProgram.mondayOfWeek(containing: .now)
    }

    func selectPlan(_ id: String?) {
        guard id != profile.planID else { return }
        profile.planID = id
        profile.programStart = id == nil ? nil : TrainingProgram.mondayOfWeek(containing: .now)
    }

    /// Where `date` falls in the active training program, including the user's moves and swaps.
    func programDay(on date: Date = .now) -> (week: Int, day: ScheduleDay, workout: ProgramWorkout?)? {
        guard let program = trainingPlan?.training,
              let (week, planned) = program.day(on: date, startedOn: programStart) else { return nil }
        let weekday = TrainingProgram.mondayBasedWeekday(of: date)
        let day = scheduledWeek(week)?[weekday - 1] ?? planned
        return (week, day, day.workout.flatMap(program.workout(id:)))
    }

    // MARK: Schedule edits

    /// Identifies a program for its edits: the person plus the program (coach's or a recommended one).
    func scheduleKey(_ plan: PersonalPlan) -> String {
        "\(plan.id)|\(profile.recommendedProgram.map { "rec-\($0.goal.rawValue)-\($0.sessionsPerWeek)" } ?? "coach")"
    }

    /// The 7 days (Mon…Sun) of a program week (1-based), with one-off and permanent edits applied.
    func scheduledWeek(_ week: Int) -> [ScheduleDay]? {
        guard let plan = trainingPlan, !plan.training.schedule.isEmpty else { return nil }
        if let oneOff = profile.scheduleEdits?[scheduleKey(plan)]?.weeks[week] { return oneOff }
        let rotation = plan.training.schedule
        return rotation[(week - 1) % rotation.count]
    }

    /// Saves a rearranged week, for that week only or for every week of the same rotation slot.
    func saveWeek(_ days: [ScheduleDay], week: Int, everyWeek: Bool) {
        guard let plan = trainingPlan, days.count == 7 else { return }
        let key = scheduleKey(plan)
        var all = profile.scheduleEdits ?? [:]
        var edits = all[key] ?? ScheduleEdits()
        if everyWeek {
            var rotation = edits.everyWeek ?? plan.training.schedule
            rotation[(week - 1) % rotation.count] = days
            edits.everyWeek = rotation
            // Later one-off changes for the same rotation slot would hide the new pattern.
            edits.weeks = edits.weeks.filter { $0.key < week || ($0.key - 1) % rotation.count != (week - 1) % rotation.count }
        } else {
            edits.weeks[week] = days
        }
        all[key] = edits
        profile.scheduleEdits = all
    }

    /// Undo: this week's one-off change, or everything back to the plan's schedule.
    func resetSchedule(week: Int? = nil) {
        guard let plan = trainingPlan else { return }
        let key = scheduleKey(plan)
        var all = profile.scheduleEdits ?? [:]
        if let week { all[key]?.weeks[week] = nil } else { all[key] = nil }
        profile.scheduleEdits = all
    }

    var hasScheduleEdits: Bool {
        guard let plan = trainingPlan, let edits = profile.scheduleEdits?[scheduleKey(plan)] else { return false }
        return edits.everyWeek != nil || !edits.weeks.isEmpty
    }

    func reset() {
        profile = UserProfile()
        hasCompletedOnboarding = false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension ProfileStore {
    /// Swaps today and tomorrow in this week (e.g. "move today's workout to tomorrow").
    func moveTodayToTomorrow() {
        guard let today = programDay(), var days = scheduledWeek(today.week) else { return }
        let index = TrainingProgram.mondayBasedWeekday(of: .now) - 1
        guard index < 6 else { return }
        days.swapAt(index, index + 1)
        saveWeek(days, week: today.week, everyWeek: false)
    }
}
