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
            body: base?.body)
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

    /// Where `date` falls in the active training program.
    func programDay(on date: Date = .now) -> (week: Int, day: ScheduleDay, workout: ProgramWorkout?)? {
        guard let program = trainingPlan?.training,
              let (week, day) = program.day(on: date, startedOn: programStart) else { return nil }
        return (week, day, day.workout.flatMap(program.workout(id:)))
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
