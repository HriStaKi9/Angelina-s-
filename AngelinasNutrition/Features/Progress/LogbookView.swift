import SwiftUI

/// The program's "Дневник": weight × reps of the last set, per exercise and week, plus past sessions.
struct LogbookView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(TrainingLog.self) private var log
    @State private var workoutID: String?

    private var lang: ContentLanguage { store.language }

    var body: some View {
        if let plan = store.activePlan {
            let selected = workoutID ?? plan.training.workouts.first?.id
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    Picker(store.t("Тренировка", "Workout"), selection: Binding(get: { selected }, set: { workoutID = $0 })) {
                        ForEach(plan.training.workouts) { Text($0.short[lang]).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.segmented)

                    if let workout = selected.flatMap(plan.training.workout(id:)) {
                        grid(plan: plan, workout: workout)
                        sessions(plan: plan, workout: workout)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle(store.t("Дневник", "Logbook"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
        }
    }

    private func grid(plan: PersonalPlan, workout: ProgramWorkout) -> some View {
        let sessions = log.workouts(planID: plan.id).filter { $0.workoutID == workout.id }
        let weeks = Array(Set(sessions.map(\.week))).sorted().suffix(6)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: workout.title[lang],
                          subtitle: store.t("Тежест × повторения на последната серия", "Weight × reps of the last set"))
            if weeks.isEmpty {
                Text(store.t("Още няма записани тренировки. Започни от екрана на тренировката.",
                             "No sessions logged yet. Start one from the workout screen."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            } else {
                Card(padding: Theme.Spacing.m) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.s) {
                            GridRow {
                                Text(store.t("Упражнение", "Exercise"))
                                ForEach(weeks, id: \.self) { Text(store.t("С\($0)", "W\($0)")) }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            Divider().overlay(Theme.Palette.hairline)
                            ForEach(workout.exercises) { item in
                                GridRow {
                                    Text("\(item.label). \(item.name[lang])")
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                    ForEach(weeks, id: \.self) { week in
                                        // Latest session of that week for this slot.
                                        let entry = sessions.first { $0.week == week }?.exercises.first { $0.slot == item.label }
                                        Text(entry?.lastDoneSet?.summary(store) ?? "–")
                                            .monospacedDigit()
                                            .foregroundStyle(entry?.option ?? 0 > 0 ? Theme.Palette.lavender : Theme.Palette.ink)
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                Text(store.t("Лилаво = направена е алтернатива.", "Purple = an alternative was done."))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    private func sessions(plan: PersonalPlan, workout: ProgramWorkout) -> some View {
        let sessions = log.workouts(planID: plan.id).filter { $0.workoutID == workout.id }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !sessions.isEmpty {
                SectionHeader(title: store.t("Тренировки", "Sessions"), subtitle: store.t("Задръж за изтриване", "Long-press to delete"))
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        Text(session.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text(store.t("Седм. \(session.week)", "Wk \(session.week)"))
                            .font(.caption.weight(.semibold)).foregroundStyle(plan.accentColor)
                    }
                    HStack(spacing: 6) {
                        Text(Duration.seconds(session.durationSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        if session.isShort { Tag(text: store.t("Кратък", "Short"), tint: Theme.Palette.lavender) }
                        if session.isDeload { Tag(text: store.t("Разтоварване", "Deload"), tint: Theme.Palette.sage) }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    ForEach(session.exercises) { exercise in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(exercise.slot). \(exercise.name[lang])")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(exercise.doneSets.map { $0.summary(store) }.joined(separator: ", "))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(Theme.Spacing.l)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.Palette.hairline))
                .contextMenu {
                    Button(store.t("Изтрий", "Delete"), systemImage: "trash", role: .destructive) { log.delete(session) }
                }
            }
        }
    }
}
