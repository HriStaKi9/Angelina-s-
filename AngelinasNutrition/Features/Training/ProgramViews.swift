import SwiftUI

enum WorkoutRoute: Hashable {
    case library
    case guide
}

/// Workouts tab: the personal training program when a plan is active, otherwise the exercise library.
struct WorkoutsView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.activePlan {
                    ProgramOverview(plan: plan)
                } else {
                    ExerciseLibraryView()
                }
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle(store.activePlan == nil ? "Workouts" : store.t("Тренировки", "Workouts"))
            .toolbar {
                if store.activePlan != nil {
                    ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
                }
            }
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
            .navigationDestination(for: ProgramWorkout.self) { ProgramWorkoutView(workout: $0) }
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .library:
                    ExerciseLibraryView()
                        .navigationTitle(store.t("Библиотека", "Exercise library"))
                case .guide:
                    if let program = store.activePlan?.training {
                        PlanGuideView(title: Localized(bg: "Прогресия и съвети", en: "Progression & tips"),
                                      sections: program.sections, adjustments: program.adjustments)
                    }
                }
            }
        }
    }
}

private struct ProgramOverview: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan

    private var program: TrainingProgram { plan.training }
    private var lang: ContentLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                WeekScheduleStrip(plan: plan)
                if let note = program.scheduleNote {
                    Text(note[lang])
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -Theme.Spacing.m)
                }
                workouts
                WarmUpCard(items: program.warmUp)
                ForEach(program.callouts) { InfoSectionView(section: $0) }
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: store.t("Още", "More"))
                    NavigationLink(value: WorkoutRoute.guide) {
                        GuideLinkRow(title: store.t("Прогресия и съвети", "Progression & tips"), systemImage: "chart.line.uptrend.xyaxis", tint: plan.accentColor)
                    }
                    NavigationLink(value: WorkoutRoute.library) {
                        GuideLinkRow(title: store.t("Библиотека с упражнения", "Exercise library"), systemImage: "books.vertical.fill", tint: Theme.Palette.lavender)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private var header: some View {
        Card(padding: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    PlanAvatar(plan: plan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.title[lang]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                        Text(program.subtitle[lang]).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    if let week = store.programDay()?.week {
                        Text(store.t("Седм. \(week)", "Week \(week)"))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(plan.accentColor)
                            .background(plan.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                Text(program.stats[lang])
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var workouts: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Тренировки", "Workouts"))
            ForEach(program.workouts) { workout in
                NavigationLink(value: workout) {
                    ProgramWorkoutCard(workout: workout, tint: plan.accentColor,
                                       isToday: store.programDay()?.workout?.id == workout.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Mon–Sun strip for the current program week; today is outlined.
struct WeekScheduleStrip: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan

    private static let bg = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]
    private static let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let monday = TrainingProgram.mondayOfWeek(containing: .now)
        let todayIndex = TrainingProgram.mondayBasedWeekday(of: .now) - 1
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: offset, to: monday) ?? monday
                if let (_, day) = plan.training.day(on: date, startedOn: store.programStart) {
                    cell(label: (store.language == .bg ? Self.bg : Self.en)[offset], day: day, isToday: offset == todayIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(label: String, day: ScheduleDay, isToday: Bool) -> some View {
        let workout = day.workout.flatMap(plan.training.workout(id:))
        let content = VStack(spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.Palette.inkSecondary)
            if let workout {
                Text(workout.short[store.language])
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.Palette.onAccent)
                    .frame(width: 32, height: 32)
                    .background(plan.accentColor, in: Circle())
            } else {
                Image(systemName: day.systemImage)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.Palette.surfaceMuted, in: Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
        .background(isToday ? plan.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .strokeBorder(isToday ? plan.accentColor : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(workout?.title[store.language] ?? day.kindTitle[store.language])")

        if let workout {
            NavigationLink(value: workout) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct ProgramWorkoutCard: View {
    @Environment(ProfileStore.self) private var store
    let workout: ProgramWorkout
    let tint: Color
    var isToday = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(workout.short[store.language])
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.Palette.onAccent)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(workout.title[store.language]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    if isToday { Tag(text: store.t("Днес", "Today"), tint: tint) }
                }
                Text([workout.duration[store.language],
                      store.t("\(workout.exercises.count) упражнения", "\(workout.exercises.count) exercises"),
                      workout.focus?[store.language]].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .strokeBorder(isToday ? tint : Theme.Palette.hairline, lineWidth: isToday ? 1.5 : 1))
    }
}

struct WarmUpCard: View {
    @Environment(ProfileStore.self) private var store
    let items: [Localized]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: store.t("Загрявка (8 мин)", "Warm-up (8 min)"))
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        BulletText(text: item[store.language], tint: Theme.Palette.apricot)
                    }
                }
            }
        }
    }
}

// MARK: - Workout detail

struct ProgramWorkoutView: View {
    @Environment(ProfileStore.self) private var store
    let workout: ProgramWorkout

    private var lang: ContentLanguage { store.language }
    private var tint: Color { store.activePlan?.accentColor ?? Theme.Palette.berry }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(workout.title[lang])
                        .font(.displayTitle)
                        .foregroundStyle(Theme.Palette.ink)
                    Text([workout.duration[lang], workout.focus?[lang]].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }

                if let warmUp = store.activePlan?.training.warmUp, !warmUp.isEmpty {
                    WarmUpCard(items: warmUp)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: store.t("Упражнения", "Exercises"),
                                  subtitle: store.t("a/b = суперсерия, без почивка между тях", "a/b = superset, no rest in between"))
                    ForEach(workout.exercises) { ProgramExerciseCard(item: $0, tint: tint) }
                }

                if let finisher = workout.finisher {
                    Callout(title: store.t("Финал", "Finisher"), items: [finisher[lang]], isWarning: false)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
    }
}

private struct ProgramExerciseCard: View {
    @Environment(ProfileStore.self) private var store
    let item: ProgramExercise
    let tint: Color

    private var lang: ContentLanguage { store.language }
    private var linked: Exercise? { item.exerciseID.flatMap(ExerciseLibrary.shared.exercise(id:)) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Text(item.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name[lang])
                            .font(.cardTitle)
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.prescription[lang])
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                    if let linked {
                        NavigationLink(value: linked) {
                            ExerciseImage(url: linked.thumbnailURL, cornerRadius: Theme.Radius.small)
                                .frame(width: 64, height: 64)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white, tint)
                                        .padding(4)
                                }
                        }
                        .accessibilityLabel(store.t("Как се прави", "How to do it"))
                    }
                }

                FlowLayout(spacing: 6) {
                    Label(item.rest[lang], systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .background(Theme.Palette.surfaceMuted, in: Capsule())
                    if let start = item.start {
                        Label(store.t("Старт: ", "Start: ") + start[lang], systemImage: "scalemass")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .background(Theme.Palette.surfaceMuted, in: Capsule())
                    }
                }

                if !item.cues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(item.cues.enumerated()), id: \.offset) { _, cue in
                            BulletText(text: cue[lang])
                        }
                    }
                }
            }
        }
    }
}
