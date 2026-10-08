import SwiftUI

struct TodayView: View {
    @Environment(ProfileStore.self) private var store

    private var profile: UserProfile { store.profile }
    private var workout: Workout { WorkoutPlanner(library: .shared).workout(for: profile) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    if let plan = store.activePlan {
                        PlanTodaySection(plan: plan)
                    } else {
                        WorkoutHeroCard(workout: workout, location: profile.location)
                        PlanLinkCard(goal: profile.goal)
                        exerciseSection(title: "Warm-up", subtitle: "Loosen up the muscles you'll train", exercises: workout.warmUp, numbered: false)
                        exerciseSection(title: "Workout", subtitle: workout.prescription.style, exercises: workout.main, numbered: true)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .toolbar {
                if store.activePlan != nil {
                    ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
                }
            }
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
            .navigationDestination(for: Meal.self) { MealDetailView(meal: $0) }
            .navigationDestination(for: ProgramWorkout.self) { ProgramWorkoutView(workout: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)
                    .locale(Locale(identifier: store.activePlan != nil && store.language == .bg ? "bg_BG" : "en_GB"))))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .textCase(.uppercase)
            Text(greeting)
                .font(.displayTitle)
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let usesPlan = store.activePlan != nil
        let part = hour < 12 ? (usesPlan ? store.t("Добро утро", "Good morning") : "Good morning")
            : hour < 18 ? (usesPlan ? store.t("Добър ден", "Good afternoon") : "Good afternoon")
            : (usesPlan ? store.t("Добър вечер", "Good evening") : "Good evening")
        let name = profile.firstName.isEmpty ? (store.activePlan?.name[store.language] ?? "") : profile.firstName
        return name.isEmpty ? part : "\(part),\n\(name)"
    }

    @ViewBuilder
    private func exerciseSection(title: String, subtitle: String, exercises: [Exercise], numbered: Bool) -> some View {
        if !exercises.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: title, subtitle: subtitle)
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    NavigationLink(value: exercise) {
                        PlannedExerciseRow(
                            exercise: exercise,
                            index: numbered ? index + 1 : nil,
                            detail: numbered ? "\(workout.prescription.sets) × \(workout.prescription.reps) · rest \(workout.prescription.restSeconds)s" : "Hold 20–30s each side"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct WorkoutHeroCard: View {
    let workout: Workout
    let location: TrainingLocation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Label(location.title, systemImage: location.systemImage)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: Capsule())
                Spacer()
                Image(systemName: "figure.strengthtraining.functional")
                    .font(.title2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's session").font(.subheadline.weight(.medium)).opacity(0.85)
                Text(workout.title).font(.system(.title, design: .rounded).weight(.bold))
            }
            HStack(spacing: Theme.Spacing.xl) {
                stat(value: "\(workout.estimatedMinutes)", unit: "min")
                stat(value: "\(workout.main.count)", unit: "exercises")
                stat(value: "\(workout.prescription.sets)×\(workout.prescription.reps)", unit: "sets × reps")
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Gradients.hero, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: Theme.Palette.berry.opacity(0.3), radius: 16, y: 8)
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(unit).font(.caption).opacity(0.85)
        }
    }
}

/// Explains how today's eating plan shapes the workout. Becomes live data once Nutrition ships.
private struct PlanLinkCard: View {
    let goal: FitnessGoal

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: goal.systemImage)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Theme.Palette.sage)
                    .background(Theme.Palette.sage.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan: \(goal.title)").font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    Text(goal.subtitle).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
    }
}

struct PlannedExerciseRow: View {
    let exercise: Exercise
    var index: Int?
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ExerciseImage(url: exercise.thumbnailURL, cornerRadius: Theme.Radius.small)
                .frame(width: 64, height: 64)
                .overlay(alignment: .topLeading) {
                    if let index {
                        Text("\(index)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.Palette.berry, in: Circle())
                            .offset(x: -6, y: -6)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                Text(detail).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
    }
}

/// Today with a personal plan: the scheduled session and the day's menu.
private struct PlanTodaySection: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @Environment(WeekMenuStore.self) private var menus
    let plan: PersonalPlan

    private var lang: ContentLanguage { store.language }

    var body: some View {
        if let today = store.programDay() {
            if let workout = today.workout {
                NavigationLink(value: workout) {
                    sessionCard(eyebrow: log.didTrain(planID: plan.id, workoutID: workout.id, on: .now)
                                    ? store.t("✓ Готово за днес", "✓ Done for today")
                                    : store.t("Днешна тренировка", "Today's workout"),
                                title: workout.title[lang],
                                detail: [workout.duration[lang], store.t("\(workout.exercises.count) упражнения", "\(workout.exercises.count) exercises")],
                                week: today.week, systemImage: "dumbbell.fill", showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                sessionCard(eyebrow: store.t("Днес", "Today"),
                            title: today.day.kindTitle[lang],
                            detail: [restDayHint(today.day.kind)],
                            week: today.week, systemImage: today.day.systemImage, showsChevron: false)
            }
        }

        let nutrition = plan.nutrition
        if let menu = menus.menu(for: plan, weekday: TrainingProgram.mondayBasedWeekday(of: .now)) {
            let totals = menu.totals(in: nutrition)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: store.t("Днешно меню", "Today's menu"),
                              subtitle: "≈ \(totals.kcal.text) kcal · \(totals.protein.text) \(store.t("г протеин", "g protein"))")
                ForEach(menu.meals(in: nutrition)) { meal in
                    NavigationLink(value: meal) { MealRow(meal: meal) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func restDayHint(_ kind: ScheduleDay.Kind) -> String {
        switch kind {
        case .walk: store.t("Разходка – крачките се броят", "A walk – steps count")
        case .steps: store.t("Ден за крачки, без силова тренировка", "Steps day, no strength session")
        case .rest: store.t("Почивка и възстановяване", "Rest and recover")
        case .workout: ""
        }
    }

    private func sessionCard(eyebrow: String, title: String, detail: [String], week: Int, systemImage: String, showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Text(store.t("Седмица \(week)", "Week \(week)"))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: Capsule())
                Spacer()
                Image(systemName: systemImage).font(.title2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).font(.subheadline.weight(.medium)).opacity(0.85)
                Text(title).font(.system(.title, design: .rounded).weight(.bold))
            }
            HStack {
                Text(detail.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if showsChevron {
                    Image(systemName: "arrow.right.circle.fill").font(.title2)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [plan.accentColor, Theme.Palette.apricot.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        )
        .shadow(color: plan.accentColor.opacity(0.3), radius: 16, y: 8)
    }
}
