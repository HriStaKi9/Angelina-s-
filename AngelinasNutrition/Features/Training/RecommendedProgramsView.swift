import SwiftUI

/// Suggests a training program for each goal (fat loss, tone, muscle, health), built for the user's
/// equipment, level and workouts per week. Starting one replaces the current program until stopped.
struct RecommendedProgramsView: View {
    @Environment(ProfileStore.self) private var store
    @State private var goal: FitnessGoal
    @State private var sessions: Int

    init(goal: FitnessGoal, sessions: Int) {
        _goal = State(initialValue: goal)
        _sessions = State(initialValue: sessions)
    }

    private var lang: ContentLanguage { store.language }
    private var tint: Color { store.trainingPlan?.accentColor ?? Theme.Palette.berry }

    private var input: ProgramRecommender.Input {
        ProgramRecommender.Input(
            goal: goal, sessionsPerWeek: sessions,
            gear: store.profile.location == .gym ? [.gym] : store.gear,
            level: store.profile.level,
            avoid: Set(store.activePlan?.training.extraExercises?.avoidCategories ?? []))
    }

    var body: some View {
        let program = ProgramRecommender.program(for: input)
        let isRunning = store.profile.recommendedProgram?.goal == goal && store.profile.recommendedProgram?.sessionsPerWeek == sessions
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: store.t("Твоята цел", "Your goal"),
                                  subtitle: store.t("Всяка цел има различна програма", "Each goal gets a different program"))
                    ForEach(FitnessGoal.allCases) { option in
                        ChoiceCard(title: lang == .bg ? option.titleBG : option.title,
                                   subtitle: summary(option), systemImage: option.systemImage,
                                   isSelected: goal == option, tint: tint) { goal = option }
                    }
                    Stepper(store.t("Тренировки седмично: \(sessions)", "Workouts per week: \(sessions)"), value: $sessions, in: 2...6)
                        .padding(Theme.Spacing.m)
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    Text(equipmentLine)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }

                preview(program)

                VStack(spacing: Theme.Spacing.s) {
                    if isRunning {
                        Label(store.t("Тази програма е активна", "This program is active"), systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.sage)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Button(store.t("Започни тази програма", "Start this program")) {
                            store.startRecommended(RecommendedProgram(goal: goal, sessionsPerWeek: sessions, program: program))
                            store.profile.goal = goal
                            store.profile.sessionsPerWeek = sessions
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: tint))
                    }
                    if store.profile.recommendedProgram != nil {
                        Button(store.activePlan != nil
                               ? store.t("Обратно към програмата от треньора", "Back to the coach's program")
                               : store.t("Спри препоръчаната програма", "Stop the recommended program"),
                               role: .destructive) { store.stopRecommended() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if store.activePlan != nil {
                        Text(store.t("Програмата от треньора остава запазена – можеш да се върнеш по всяко време. Дневникът се води отделно за всяка програма.",
                                     "The coach's program stays saved – switch back any time. Each program keeps its own logbook."))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(store.t("Препоръчани програми", "Recommended programs"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func preview(_ program: TrainingProgram) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Card(padding: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(program.title[lang]).font(.sectionTitle).foregroundStyle(Theme.Palette.ink)
                    Text(program.subtitle[lang] + " · " + program.stats[lang])
                        .font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                    HStack(spacing: 4) {
                        ForEach(Array((program.schedule.first ?? []).enumerated()), id: \.offset) { offset, day in
                            VStack(spacing: 2) {
                                Text(PlanSummary.shortWeekday(offset + 1, lang)).font(.caption2).foregroundStyle(Theme.Palette.inkSecondary)
                                Text(day.workout.flatMap(program.workout(id:))?.short[lang] ?? "·")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(day.kind == .workout ? Theme.Palette.onAccent : Theme.Palette.inkSecondary)
                                    .frame(width: 28, height: 28)
                                    .background(day.kind == .workout ? tint : Theme.Palette.surfaceMuted, in: Circle())
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            }
            ForEach(program.workouts) { workout in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("\(workout.title[lang]) · \(workout.duration[lang])").font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    Card(padding: Theme.Spacing.m) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(workout.exercises) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.name[lang]).font(.subheadline).foregroundStyle(Theme.Palette.ink)
                                    Spacer(minLength: Theme.Spacing.s)
                                    Text(item.prescription[lang]).font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(Theme.Palette.inkSecondary)
                                }
                            }
                            if let finisher = workout.finisher {
                                Text(finisher[lang]).font(.caption).foregroundStyle(Theme.Palette.inkSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var equipmentLine: String {
        let gear = store.profile.location == .gym ? store.t("фитнес зала", "a gym")
            : store.gear.map { $0.title[lang] }.sorted().joined(separator: ", ")
        let levelBG = ["beginner": "начинаещ", "intermediate": "среден", "expert": "напреднал"][store.profile.level.rawValue] ?? ""
        return store.t("Съставена за: \(gear) · ниво \(levelBG). Смени оборудването в Профил.",
                       "Built for: \(gear) · \(store.profile.level.title.lowercased()) level. Change equipment in Profile.")
    }

    private func summary(_ goal: FitnessGoal) -> String {
        switch goal {
        case .loseFat: store.t("Повече повторения, кратки почивки, финал с кардио", "Higher reps, short rests, a cardio finisher")
        case .tone: store.t("Средни повторения, акцент върху седалището", "Moderate reps with extra glute work")
        case .buildMuscle: store.t("Тежки основни упражнения 4 × 6–10, дълги почивки", "Heavy main lifts 4 × 6–10, longer rests")
        case .maintain: store.t("Балансирано цяло тяло, 3 × 10–12", "Balanced full body, 3 × 10–12")
        }
    }
}

/// Entry card for the recommended programs (Workouts tab).
struct RecommendedProgramsCard: View {
    @Environment(ProfileStore.self) private var store
    let tint: Color

    var body: some View {
        let running = store.profile.recommendedProgram
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Препоръчани програми", "Recommended programs")).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                Text(running.map { store.t("Активна: \($0.program.title.bg)", "Active: \($0.program.title.en)") }
                     ?? store.t("Програма според целта: \(store.profile.goal.titleBG.lowercased())", "A program for your goal: \(store.profile.goal.title.lowercased())"))
                    .font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
    }
}
